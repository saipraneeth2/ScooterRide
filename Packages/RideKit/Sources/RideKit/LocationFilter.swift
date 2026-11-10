import Foundation

public enum RejectionReason: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case notRecording          // ride is not active (idle, paused or ended)
    case invalidCoordinate     // negative accuracy, NaN, out of range, or (0,0)
    case poorAccuracy          // horizontal accuracy worse than the configured limit
    case stale                 // fix is older than the configured age
    case outOfOrder            // timestamp earlier than the previous accepted fix
    case duplicate             // same timestamp as the previous accepted fix
    case implausibleSpeed      // reported speed above the plausibility cap
    case implausibleJump       // position jump implies a speed above the cap
    case beforeSegmentStart    // timestamped before the ride (or resume) started
}

public enum FilterDecision: Equatable, Sendable {
    case accept
    case reject(RejectionReason)

    public var isAccepted: Bool { self == .accept }
}

public struct LocationFilterConfig: Codable, Equatable, Sendable {
    /// Reject fixes whose horizontal accuracy is worse than this (meters).
    public var maxHorizontalAccuracy: Double
    /// Reject fixes older than this when they arrive (seconds); Core Location can deliver cached fixes.
    public var maxSampleAge: TimeInterval
    /// Plausibility cap (m/s). The US E3 Pro is rated about 20 mph; 40 mph leaves room
    /// for descents while still rejecting obvious GPS spikes.
    public var maxPlausibleSpeed: Double

    public init(maxHorizontalAccuracy: Double = 25, maxSampleAge: TimeInterval = 10,
                maxPlausibleSpeed: Double = Units.metersPerSecond(fromMph: 40)) {
        self.maxHorizontalAccuracy = maxHorizontalAccuracy
        self.maxSampleAge = maxSampleAge
        self.maxPlausibleSpeed = maxPlausibleSpeed
    }
}

/// Decides whether a GPS fix is trustworthy enough to record.
public struct LocationFilter: Codable, Equatable, Sendable {
    public var config: LocationFilterConfig

    public init(config: LocationFilterConfig = LocationFilterConfig()) { self.config = config }

    /// - Parameters:
    ///   - previous: the last accepted fix in the current (unpaused) segment, if any.
    ///   - now: arrival time, used for the staleness check.
    public func evaluate(_ s: LocationSample, previous: LocationSample?, now: Date) -> FilterDecision {
        guard s.hasValidCoordinate else { return .reject(.invalidCoordinate) }
        guard s.horizontalAccuracy <= config.maxHorizontalAccuracy else { return .reject(.poorAccuracy) }
        guard now.timeIntervalSince(s.timestamp) <= config.maxSampleAge else { return .reject(.stale) }
        if let speed = s.speed, speed > config.maxPlausibleSpeed { return .reject(.implausibleSpeed) }
        if let p = previous {
            let dt = s.timestamp.timeIntervalSince(p.timestamp)
            if dt < 0 { return .reject(.outOfOrder) }
            if dt == 0 { return .reject(.duplicate) }
            // Only call it a jump if the move is larger than both fixes' uncertainty allows.
            let d = GeoMath.distance(p, s)
            let slack = p.horizontalAccuracy + s.horizontalAccuracy
            if d > slack, (d - slack) / dt > config.maxPlausibleSpeed { return .reject(.implausibleJump) }
        }
        return .accept
    }
}
