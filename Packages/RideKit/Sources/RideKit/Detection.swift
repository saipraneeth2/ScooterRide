import Foundation

// Smart Detection: optional, off by default, and only ever suggests.
//
// Nothing here starts, ends or changes a ride. Each detector turns GPS speed and Core Motion
// readings into a suggestion that the rider must confirm with a tap. Every result is an
// estimate: Core Motion has no "scooter" activity, and GPS speed alone can't tell a scooter
// from a bicycle.

// MARK: - Stop suggestion (during a ride)

/// Suggests ending a ride after a sustained stop. Needs continuous evidence for the whole
/// window: slow GPS speed (with motion, if known, not riding-like), or, when GPS has no
/// speed, Core Motion saying stationary or on foot. A gap in evidence starts the clock over.
public struct StopDetector: Sendable {
    public struct Config: Sendable {
        /// Below this (≈ 3 mph) counts as stopped or walking the scooter.
        public var stoppedBelow: Double = 1.3
        /// Moving again at or above this (≈ 6.7 mph) re-arms the detector.
        public var movingAbove: Double = 3.0
        /// How long the stop must last before suggesting (3 min: longer than most red lights).
        public var window: TimeInterval = 180
        /// Readings further apart than this don't count as continuous evidence.
        public var maxGap: TimeInterval = 45
        /// After "Keep Riding", stay quiet this long.
        public var snooze: TimeInterval = 600
        public init() {}
    }

    public var config: Config
    public private(set) var stoppedSince: Date?
    public private(set) var hasSuggested = false
    private var lastReading: Date?
    private var snoozedUntil: Date?

    public init(config: Config = Config()) { self.config = config }

    /// Feeds one reading (a GPS fix's smoothed speed, or a periodic check with `speed` nil).
    /// Returns true exactly when the rider should be asked whether to end the ride.
    public mutating func update(speed: Double?, motion: MotionKind?, at time: Date) -> Bool {
        defer { lastReading = time }
        let movingAgain = (speed.map { $0 >= config.movingAbove } ?? false) || (motion?.isRidingLike == true && speed == nil)
        if movingAgain {
            stoppedSince = nil
            hasSuggested = false
            return false
        }
        if let last = lastReading, time.timeIntervalSince(last) > config.maxGap { stoppedSince = nil }

        let stoppedEvidence: Bool
        if let speed {
            stoppedEvidence = speed < config.stoppedBelow && motion?.isRidingLike != true
        } else if let motion {
            stoppedEvidence = motion == .stationary || motion.isOnFoot
        } else {
            stoppedEvidence = false   // no GPS speed and no motion: no evidence either way
        }
        guard stoppedEvidence else {
            stoppedSince = nil
            return false
        }
        if stoppedSince == nil { stoppedSince = time }
        if let until = snoozedUntil, time < until { return false }
        guard !hasSuggested, let since = stoppedSince, time.timeIntervalSince(since) >= config.window else { return false }
        hasSuggested = true
        return true
    }

    /// The rider chose to keep riding.
    public mutating func dismiss(at time: Date) {
        snoozedUntil = time.addingTimeInterval(config.snooze)
        stoppedSince = nil
        hasSuggested = false
    }

    public mutating func reset() { self = StopDetector(config: config) }
}

// MARK: - Start suggestion (app open, not recording)

public enum StartReason: Equatable, Sendable {
    /// GPS shows sustained movement at scooter-like speed (median, m/s).
    case movingAtScooterSpeed(medianSpeed: Double)
    /// The scooter the rider picked is advertising nearby, so it's probably switched on.
    case scooterNearby
}

/// Suggests starting a ride while ScooterRide is open but not recording.
public struct StartDetector: Sendable {
    public struct Config: Sendable {
        /// ≈ 6 mph: faster than walking.
        public var minSpeed: Double = 2.7
        /// ≈ 23 mph: an E3 Pro tops out near 20 mph; faster is probably not this scooter.
        public var maxSpeed: Double = 10.3
        public var window: TimeInterval = 15
        public var minReadings = 5
        /// Share of readings in the window that must be in range.
        public var minShareInRange = 0.8
        /// Ignore fixes less accurate than this.
        public var maxAccuracy: Double = 20
        /// Ignore Doppler speeds less accurate than this.
        public var maxSpeedAccuracy: Double = 2.5
        /// Signal needed to call the scooter "nearby" (dBm).
        public var nearbyRSSI = -85
        /// After "Not now", stay quiet this long.
        public var snooze: TimeInterval = 300
        public init() {}
    }

    public var config: Config
    private var readings: [(time: Date, speed: Double)] = []
    private var snoozedUntil: Date?
    public private(set) var suggested: StartReason?

    public init(config: Config = Config()) { self.config = config }

    /// Feeds one GPS fix. Returns a reason when a suggestion should be shown now.
    public mutating func update(_ sample: LocationSample, at now: Date) -> StartReason? {
        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= config.maxAccuracy,
              let speed = sample.speed, speed >= 0,
              (sample.speedAccuracy ?? 0) <= config.maxSpeedAccuracy else { return nil }
        readings.append((sample.timestamp, speed))
        readings.removeAll { now.timeIntervalSince($0.time) > config.window }
        guard readings.count >= config.minReadings else { return nil }
        let inRange = readings.filter { $0.speed >= config.minSpeed && $0.speed <= config.maxSpeed }
        guard Double(inRange.count) / Double(readings.count) >= config.minShareInRange else { return nil }
        let sorted = readings.map(\.speed).sorted()
        return suggest(.movingAtScooterSpeed(medianSpeed: sorted[sorted.count / 2]), at: now)
    }

    /// Feeds one Bluetooth sighting of the rider's chosen scooter.
    public mutating func scooterSeen(rssi: Int, at now: Date) -> StartReason? {
        guard rssi >= config.nearbyRSSI, rssi < 0 else { return nil }
        return suggest(.scooterNearby, at: now)
    }

    public mutating func dismiss(at now: Date) {
        snoozedUntil = now.addingTimeInterval(config.snooze)
        suggested = nil
        readings.removeAll()
    }

    public mutating func reset() { self = StartDetector(config: config) }

    private mutating func suggest(_ reason: StartReason, at now: Date) -> StartReason? {
        if let until = snoozedUntil, now < until { return nil }
        guard suggested == nil else { return nil }
        suggested = reason
        return reason
    }
}

// MARK: - Ride-type estimate (saved rides)

public enum RideType: String, Codable, Sendable {
    case scooterLike, mostlyWalking, fasterThanScooter, notEnoughData
}

public struct RideTypeEstimate: Equatable, Sendable {
    public var type: RideType
    /// Median GPS speed while moving (m/s).
    public var medianMovingSpeed: Double?
    /// Moving time, from GPS (s).
    public var movingSeconds: TimeInterval
    /// Share of moving time above `RideTypeEstimator.fasterThanScooter`.
    public var fastShare: Double
    /// Core Motion: share of classified time that was cycling or automotive, if recorded.
    public var ridingMotionShare: Double?
    /// Core Motion: share of classified time on foot, if recorded.
    public var onFootMotionShare: Double?
}

/// Labels a finished ride from its GPS speeds and, when recorded, Core Motion summary.
public enum RideTypeEstimator {
    /// Slower than this (≈ 3 mph) counts as not moving.
    public static let movingAbove = 1.3
    /// Median below this (≈ 5 mph) looks like walking.
    public static let walkingBelow = 2.2
    /// Faster than this (≈ 25 mph) is beyond an E3 Pro, even downhill.
    public static let fasterThanScooter = 11.2
    public static let minMovingSeconds: TimeInterval = 30
    /// Gaps longer than this between fixes don't count as moving time.
    static let maxStep: TimeInterval = 5

    public static func estimate(_ ride: RideSession) -> RideTypeEstimate {
        var moving: [(speed: Double, dt: TimeInterval)] = []
        let points = ride.route
        for (i, p) in points.enumerated() {
            guard let v = p.estimatedSpeed, v >= movingAbove else { continue }
            let next = i + 1 < points.count && points[i + 1].segment == p.segment ? points[i + 1].sample.timestamp : nil
            let dt = next.map { min(maxStep, max(0, $0.timeIntervalSince(p.sample.timestamp))) } ?? 1
            moving.append((v, dt))
        }
        let movingSeconds = moving.reduce(0) { $0 + $1.dt }
        let fastSeconds = moving.filter { $0.speed > fasterThanScooter }.reduce(0) { $0 + $1.dt }
        let fastShare = movingSeconds > 0 ? fastSeconds / movingSeconds : 0
        let sorted = moving.map(\.speed).sorted()
        let median = sorted.isEmpty ? nil : sorted[sorted.count / 2]
        let riding = ride.motion?.share { $0.isRidingLike }
        let onFoot = ride.motion?.share { $0.isOnFoot }
        let motionTotal = ride.motion?.total ?? 0

        let type: RideType
        if movingSeconds < minMovingSeconds || median == nil {
            type = .notEnoughData
        } else if fastShare >= 0.2 || (median ?? 0) > fasterThanScooter {
            type = .fasterThanScooter
        } else if (median ?? 0) < walkingBelow || (motionTotal >= minMovingSeconds && (onFoot ?? 0) >= 0.5) {
            type = .mostlyWalking
        } else {
            type = .scooterLike
        }
        return RideTypeEstimate(type: type, medianMovingSpeed: median, movingSeconds: movingSeconds,
                                fastShare: fastShare, ridingMotionShare: riding, onFootMotionShare: onFoot)
    }
}

extension RideTypeEstimate {
    public static let caveat = "An estimate from GPS speed and, when recorded, motion activity. It can't tell a scooter from a bicycle."

    public var title: String {
        switch type {
        case .scooterLike: return "Scooter-like riding"
        case .mostlyWalking: return "Mostly walking"
        case .fasterThanScooter: return "Faster than an E3 Pro (car?)"
        case .notEnoughData: return "Not enough movement to tell"
        }
    }

    public var details: [String] {
        var lines: [String] = []
        if let median = medianMovingSpeed { lines.append("Median moving speed: \(RideFormat.speed(median)) mph") }
        lines.append("Moving time: \(RideFormat.duration(movingSeconds))")
        if fastShare > 0 { lines.append("Above 25 mph: \(Int((fastShare * 100).rounded()))% of moving time") }
        if let riding = ridingMotionShare, let onFoot = onFootMotionShare {
            lines.append("Motion: \(Int((riding * 100).rounded()))% riding-like, \(Int((onFoot * 100).rounded()))% on foot")
        } else {
            lines.append("Motion: not recorded")
        }
        return lines
    }
}

// MARK: - iPhone riding alert (background)

/// One Core Motion activity from the iPhone's history; it lasts until the next one starts.
public struct MotionActivitySpan: Equatable, Sendable {
    public var start: Date
    public var kind: MotionKind
    public init(start: Date, kind: MotionKind) { self.start = start; self.kind = kind }
}

public enum RidingAlertDecision: Equatable, Sendable {
    case alert
    case skip(String)
}

/// Decides whether the iPhone should send a "riding?" notification after the system wakes it
/// for a significant location change.
public struct RidingAlertPolicy: Sendable {
    /// Riding-like motion needed in the look-back window.
    public var minRidingSeconds: TimeInterval = 60
    public var lookBack: TimeInterval = 300
    /// At most one alert this often.
    public var minInterval: TimeInterval = 1800
    /// Faster than this between location updates is probably a car (≈ 25 mph).
    public var maxSpeed: Double = 11.2

    public init() {}

    /// - Parameters:
    ///   - activities: Core Motion history, oldest first, covering at least `lookBack`.
    ///   - impliedSpeed: distance / time between the last two location updates (m/s), if known.
    public func decide(activities: [MotionActivitySpan], now: Date, lastAlert: Date?,
                       watchIsRecording: Bool, impliedSpeed: Double?) -> RidingAlertDecision {
        if watchIsRecording { return .skip("a ride is already recording on Apple Watch") }
        if let lastAlert, now.timeIntervalSince(lastAlert) < minInterval { return .skip("alerted recently") }
        if let impliedSpeed, impliedSpeed > maxSpeed { return .skip("moving faster than a scooter") }
        guard let latest = activities.last, latest.kind.isRidingLike else { return .skip("not riding now") }
        // Automotive without a speed check is too likely to be a car or bus.
        if latest.kind == .automotive, impliedSpeed == nil { return .skip("automotive with no speed to check") }
        let windowStart = now.addingTimeInterval(-lookBack)
        var riding: TimeInterval = 0
        for (i, a) in activities.enumerated() where a.kind.isRidingLike {
            let start = max(a.start, windowStart)
            let end = i + 1 < activities.count ? activities[i + 1].start : now
            if end > start { riding += end.timeIntervalSince(start) }
        }
        return riding >= minRidingSeconds ? .alert : .skip("not enough riding-like motion yet")
    }
}
