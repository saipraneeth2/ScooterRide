import Foundation

/// Core Motion's activity estimate, reduced to one kind. Core Motion has no "scooter"
/// activity: a scooter ride may show up as cycling, automotive or unknown, which is why
/// ScooterRide only ever treats this as one input to an estimate.
public enum MotionKind: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case stationary, walking, running, cycling, automotive, unknown

    /// Moving on wheels, as far as Core Motion can tell.
    public var isRidingLike: Bool { self == .cycling || self == .automotive }
    /// On foot.
    public var isOnFoot: Bool { self == .walking || self == .running }

    /// Picks one kind from Core Motion's flags. Several can be true at once (a stopped car is
    /// automotive and stationary), so vehicle kinds win. Low confidence (0) counts as unknown.
    public static func classify(automotive: Bool, cycling: Bool, running: Bool, walking: Bool,
                                stationary: Bool, confidence: Int) -> MotionKind {
        guard confidence >= 1 else { return .unknown }
        if automotive { return .automotive }
        if cycling { return .cycling }
        if running { return .running }
        if walking { return .walking }
        if stationary { return .stationary }
        return .unknown
    }
}

/// Seconds of recording time spent in each motion kind. Optional on a ride: older rides,
/// and rides recorded with Smart Detection off, have none.
public struct MotionSummary: Codable, Equatable, Sendable {
    public var seconds: [MotionKind: TimeInterval] = [:]

    public init(seconds: [MotionKind: TimeInterval] = [:]) { self.seconds = seconds }

    public var total: TimeInterval { seconds.values.reduce(0, +) }

    /// Share of the classified time (unknown excluded) spent in kinds matching `predicate`.
    public func share(where predicate: (MotionKind) -> Bool) -> Double? {
        let known = seconds.filter { $0.key != .unknown }
        let total = known.values.reduce(0, +)
        guard total > 0 else { return nil }
        return known.filter { predicate($0.key) }.values.reduce(0, +) / total
    }
}

#if os(iOS) || os(watchOS)
import CoreMotion

extension MotionKind {
    public init(_ activity: CMMotionActivity) {
        self = Self.classify(automotive: activity.automotive, cycling: activity.cycling,
                             running: activity.running, walking: activity.walking,
                             stationary: activity.stationary, confidence: activity.confidence.rawValue)
    }
}
#endif
