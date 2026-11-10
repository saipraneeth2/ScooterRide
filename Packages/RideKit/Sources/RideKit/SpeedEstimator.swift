import Foundation

/// Turns accepted GPS fixes into a displayed speed estimate.
///
/// - Uses Core Location's Doppler speed when its reported accuracy is good.
/// - Otherwise derives speed from distance / time between consecutive fixes.
/// - Smooths with a median of the last few estimates, so a single spike cannot
///   reach the display or the maximum.
public struct SpeedEstimator: Codable, Equatable, Sendable {
    /// Trust reported speed only when its accuracy is at least this good (m/s).
    public var maxReportedSpeedAccuracy: Double
    /// Below this (m/s, about 1.1 mph) the scooter is treated as stopped.
    public var stationaryThreshold: Double
    /// Number of estimates in the median window.
    public var window: Int
    /// Derived speeds over gaps longer than this (seconds) are not trusted.
    public var maxDerivationGap: TimeInterval

    public private(set) var recent: [Double] = []

    public init(maxReportedSpeedAccuracy: Double = 2.5, stationaryThreshold: Double = 0.5,
                window: Int = 3, maxDerivationGap: TimeInterval = 10) {
        self.maxReportedSpeedAccuracy = maxReportedSpeedAccuracy
        self.stationaryThreshold = stationaryThreshold
        self.window = max(1, window)
        self.maxDerivationGap = maxDerivationGap
    }

    /// A single raw estimate for `sample`, or nil if neither method is reliable.
    public func rawSpeed(for sample: LocationSample, previous: LocationSample?) -> Double? {
        if let v = sample.speed, v >= 0 {
            if let acc = sample.speedAccuracy {
                if acc <= maxReportedSpeedAccuracy { return v }
            } else {
                return v   // older OS versions do not report speedAccuracy
            }
        }
        guard let p = previous else { return nil }
        let dt = sample.timestamp.timeIntervalSince(p.timestamp)
        guard dt > 0, dt <= maxDerivationGap else { return nil }
        return GeoMath.distance(p, sample) / dt
    }

    /// Adds an estimate and returns the smoothed (median) speed, clamped to 0 when stopped.
    public mutating func push(_ raw: Double) -> Double {
        recent.append(raw)
        if recent.count > window { recent.removeFirst(recent.count - window) }
        let sorted = recent.sorted()
        let median = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        return median < stationaryThreshold ? 0 : median
    }

    /// True once the window holds enough estimates for the median to reject a lone spike.
    public var isSettled: Bool { recent.count >= min(window, 2) }

    public mutating func reset() { recent.removeAll() }
}
