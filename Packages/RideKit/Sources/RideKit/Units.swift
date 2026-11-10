import Foundation

/// Unit conversions. Internally everything is SI (meters, seconds, m/s).
public enum Units {
    public static let mphPerMetersPerSecond = 2.2369362920544
    public static let metersPerMile = 1609.344

    public static func mph(fromMetersPerSecond v: Double) -> Double { v * mphPerMetersPerSecond }
    public static func metersPerSecond(fromMph v: Double) -> Double { v / mphPerMetersPerSecond }
    public static func miles(fromMeters m: Double) -> Double { m / metersPerMile }
}

/// Display formatting. Speeds are always GPS estimates; callers label them as such.
public enum RideFormat {
    /// "12.3" (mph), or "--" when there is no current estimate.
    public static func speed(_ metersPerSecond: Double?) -> String {
        guard let v = metersPerSecond, v.isFinite, v >= 0 else { return "--" }
        return String(format: "%.1f", Units.mph(fromMetersPerSecond: v))
    }

    /// "1.24 mi"
    public static func distance(_ meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "-- mi" }
        return String(format: "%.2f mi", Units.miles(fromMeters: meters))
    }

    /// "4:05" or "1:02:03"
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
