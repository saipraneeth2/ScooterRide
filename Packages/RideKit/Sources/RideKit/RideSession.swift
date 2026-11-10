import Foundation

public enum RideSource: String, Codable, Sendable {
    case watch, phone
}

/// A period during which the ride was actively recording (between start/resume and pause/end).
public struct ActiveInterval: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date?
    public init(start: Date, end: Date? = nil) { self.start = start; self.end = end }

    public func duration(at now: Date) -> TimeInterval { max(0, (end ?? now).timeIntervalSince(start)) }
}

/// One accepted GPS fix in the recorded route. `segment` increases after each pause,
/// so maps never draw a line across a paused stretch.
public struct RoutePoint: Codable, Equatable, Sendable {
    public var sample: LocationSample
    public var segment: Int
    /// Smoothed GPS-estimated speed at this point (m/s), if one was available.
    public var estimatedSpeed: Double?

    public init(sample: LocationSample, segment: Int, estimatedSpeed: Double?) {
        self.sample = sample; self.segment = segment; self.estimatedSpeed = estimatedSpeed
    }
}

/// A scooter ride. Deliberately NOT a HealthKit workout: it never contributes to
/// Activity rings, exercise minutes or calories.
public struct RideSession: Codable, Identifiable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public let id: UUID
    public var source: RideSource
    public var startDate: Date
    public var endDate: Date?
    public var intervals: [ActiveInterval]
    public var route: [RoutePoint]
    public var distanceMeters: Double
    public var maxSpeedMetersPerSecond: Double?
    public var acceptedSampleCount: Int
    public var rejectedSampleCounts: [RejectionReason: Int]
    /// True when the ride was rebuilt from a checkpoint after the app was terminated mid-ride.
    public var recovered: Bool

    public init(id: UUID = UUID(), source: RideSource, startDate: Date) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.source = source
        self.startDate = startDate
        endDate = nil
        intervals = [ActiveInterval(start: startDate)]
        route = []
        distanceMeters = 0
        maxSpeedMetersPerSecond = nil
        acceptedSampleCount = 0
        rejectedSampleCounts = [:]
        recovered = false
    }

    /// Recording time, excluding pauses.
    public func activeDuration(at now: Date) -> TimeInterval {
        intervals.reduce(0) { $0 + $1.duration(at: endDate ?? now) }
    }

    /// Distance / active time. Nil until there is meaningful time and distance.
    public func averageSpeed(at now: Date) -> Double? {
        let t = activeDuration(at: now)
        guard t >= 1, distanceMeters > 0 else { return nil }
        return distanceMeters / t
    }

    public var rejectedSampleTotal: Int { rejectedSampleCounts.values.reduce(0, +) }
    public var isFinished: Bool { endDate != nil }
}
