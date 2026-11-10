import Foundation

/// A platform-neutral copy of one Core Location fix. The app converts CLLocation
/// into this type, so filtering and metrics can be tested without CoreLocation.
public struct LocationSample: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?
    /// Meters. Negative means the coordinate is invalid (Core Location convention).
    public var horizontalAccuracy: Double
    /// Meters per second, or nil when Core Location reported it as invalid (< 0).
    public var speed: Double?
    /// Meters per second, or nil when invalid.
    public var speedAccuracy: Double?
    /// Degrees from true north, or nil when invalid.
    public var course: Double?

    public init(timestamp: Date, latitude: Double, longitude: Double, altitude: Double? = nil,
                horizontalAccuracy: Double, speed: Double? = nil, speedAccuracy: Double? = nil,
                course: Double? = nil) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.course = course
    }

    public var hasValidCoordinate: Bool {
        horizontalAccuracy >= 0 && latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
            && !(latitude == 0 && longitude == 0)
    }
}

public enum GeoMath {
    /// Mean Earth radius (IUGG), meters.
    public static let earthRadius = 6_371_008.8

    /// Great-circle (haversine) distance in meters. Within ~0.5% of the WGS-84 geodesic,
    /// which is far below GPS error at scooter scales.
    public static func distance(_ a: LocationSample, _ b: LocationSample) -> Double {
        distance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
    }

    public static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }
}
