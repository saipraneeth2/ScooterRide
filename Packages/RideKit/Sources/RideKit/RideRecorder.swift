import Foundation

public enum RideState: String, Codable, Sendable {
    case idle, active, paused, ended
}

public enum RideRecorderError: Error, Equatable, Sendable {
    case invalidTransition(from: RideState, action: String)
}

public enum GPSStatus: String, Sendable {
    case searching   // recording, but no accepted fix yet
    case good        // recent fix, accuracy <= 10 m
    case fair        // recent fix, accuracy <= filter limit
    case lost        // no accepted fix for a while
    case off         // not recording
}

public struct RideMetrics: Equatable, Sendable {
    public var state: RideState
    public var activeDuration: TimeInterval
    public var distanceMeters: Double
    /// Smoothed GPS-estimated speed (m/s). Nil when there is no recent reliable fix.
    public var currentSpeed: Double?
    public var averageSpeed: Double?
    public var maxSpeed: Double?
    public var gps: GPSStatus
    public var acceptedSamples: Int
    public var rejectedSamples: Int
}

/// The ride state machine plus metric accumulation. Pure value type: the app feeds it
/// LocationSamples and dates, which makes it fully deterministic in tests.
///
/// idle --start--> active --pause--> paused --resume--> active --end--> ended
///                                    paused --end--> ended
public struct RideRecorder: Sendable {
    public private(set) var state: RideState = .idle
    public private(set) var session: RideSession?
    public private(set) var lastAcceptedSample: LocationSample?
    public private(set) var lastDecision: FilterDecision?
    public var filter: LocationFilter
    public private(set) var estimator: SpeedEstimator

    /// Current speed is shown as "--" when the last accepted fix is older than this.
    public var speedStaleAfter: TimeInterval = 5
    /// GPS status turns "lost" after this long without an accepted fix.
    public var gpsLostAfter: TimeInterval = 10

    private var segment = 0
    private var previousInSegment: LocationSample?
    private var distanceAnchor: LocationSample?
    private var smoothedSpeed: Double?

    public init(filter: LocationFilter = LocationFilter(), estimator: SpeedEstimator = SpeedEstimator()) {
        self.filter = filter
        self.estimator = estimator
    }

    // MARK: Transitions

    public mutating func start(id: UUID = UUID(), at date: Date, source: RideSource) throws {
        guard state == .idle else { throw RideRecorderError.invalidTransition(from: state, action: "start") }
        session = RideSession(id: id, source: source, startDate: date)
        state = .active
        segment = 0
        resetSegmentTracking()
        lastAcceptedSample = nil
        lastDecision = nil
    }

    public mutating func pause(at date: Date) throws {
        guard state == .active, var s = session else { throw RideRecorderError.invalidTransition(from: state, action: "pause") }
        closeOpenInterval(&s, at: date)
        session = s
        state = .paused
        resetSegmentTracking()
    }

    public mutating func resume(at date: Date) throws {
        guard state == .paused, var s = session else { throw RideRecorderError.invalidTransition(from: state, action: "resume") }
        s.intervals.append(ActiveInterval(start: date))
        session = s
        segment += 1
        state = .active
        resetSegmentTracking()
    }

    /// Ends the ride and returns the finished session. Allowed from active or paused.
    @discardableResult
    public mutating func end(at date: Date) throws -> RideSession {
        guard state == .active || state == .paused, var s = session else {
            throw RideRecorderError.invalidTransition(from: state, action: "end")
        }
        closeOpenInterval(&s, at: date)
        s.endDate = date
        session = s
        state = .ended
        resetSegmentTracking()
        return s
    }

    /// Returns to idle after a ride has ended (or discards nothing if already idle).
    public mutating func reset() {
        state = .idle
        session = nil
        lastAcceptedSample = nil
        lastDecision = nil
        segment = 0
        resetSegmentTracking()
    }

    // MARK: GPS input

    @discardableResult
    public mutating func ingest(_ sample: LocationSample, now: Date) -> FilterDecision {
        guard state == .active, var s = session else {
            lastDecision = .reject(.notRecording)
            return .reject(.notRecording)
        }
        var decision = filter.evaluate(sample, previous: previousInSegment, now: now)
        // A fix timestamped before Start/Resume belongs to before the ride (seen on a real
        // watch: the first fix was 0.4 s older than the Start tap). Keep it out of the route.
        if decision == .accept, let segmentStart = s.intervals.last?.start, sample.timestamp < segmentStart {
            decision = .reject(.beforeSegmentStart)
        }
        lastDecision = decision
        guard decision == .accept else {
            if case .reject(let reason) = decision { s.rejectedSampleCounts[reason, default: 0] += 1 }
            session = s
            return decision
        }

        // Speed
        if let raw = estimator.rawSpeed(for: sample, previous: previousInSegment) {
            let smoothed = estimator.push(raw)
            smoothedSpeed = smoothed
            if estimator.isSettled {
                s.maxSpeedMetersPerSecond = max(s.maxSpeedMetersPerSecond ?? 0, smoothed)
            }
        }

        // Distance: count movement, ignore stationary jitter inside the GPS error circle.
        if let anchor = distanceAnchor {
            let d = GeoMath.distance(anchor, sample)
            let clearlyMoving = (sample.speed ?? 0) >= 1.0
            let threshold = max(5, anchor.horizontalAccuracy, sample.horizontalAccuracy)
            if clearlyMoving || d >= threshold {
                s.distanceMeters += d
                distanceAnchor = sample
            }
        } else {
            distanceAnchor = sample
        }

        s.route.append(RoutePoint(sample: sample, segment: segment, estimatedSpeed: smoothedSpeed))
        s.acceptedSampleCount += 1
        session = s
        previousInSegment = sample
        lastAcceptedSample = sample
        return .accept
    }

    // MARK: Metrics

    public func metrics(at now: Date) -> RideMetrics {
        guard let s = session else {
            return RideMetrics(state: state, activeDuration: 0, distanceMeters: 0, currentSpeed: nil,
                               averageSpeed: nil, maxSpeed: nil, gps: .off, acceptedSamples: 0, rejectedSamples: 0)
        }
        var current: Double? = nil
        var gps: GPSStatus = .off
        if state == .active {
            if let last = previousInSegment {
                let age = now.timeIntervalSince(last.timestamp)
                if age <= speedStaleAfter { current = smoothedSpeed }
                if age > gpsLostAfter { gps = .lost }
                else { gps = last.horizontalAccuracy <= 10 ? .good : .fair }
            } else {
                gps = .searching
            }
        }
        return RideMetrics(state: state, activeDuration: s.activeDuration(at: now), distanceMeters: s.distanceMeters,
                           currentSpeed: current, averageSpeed: s.averageSpeed(at: now),
                           maxSpeed: s.maxSpeedMetersPerSecond, gps: gps,
                           acceptedSamples: s.acceptedSampleCount, rejectedSamples: s.rejectedSampleTotal)
    }

    // MARK: Helpers

    private mutating func resetSegmentTracking() {
        previousInSegment = nil
        distanceAnchor = nil
        smoothedSpeed = nil
        estimator.reset()
    }

    private func closeOpenInterval(_ s: inout RideSession, at date: Date) {
        if let i = s.intervals.lastIndex(where: { $0.end == nil }) {
            s.intervals[i].end = max(date, s.intervals[i].start)
        }
    }
}
