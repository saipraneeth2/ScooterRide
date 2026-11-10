import Foundation
@testable import RideKit

/// SYNTHETIC GPS tracks for tests. Nothing here was recorded from a real device.
enum Synthetic {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let lat0 = 37.3349
    static let lon0 = -122.0090
    /// Meters per degree of latitude on the mean-radius sphere used by GeoMath.
    static let metersPerDegreeLat = GeoMath.earthRadius * .pi / 180

    static func sample(northMeters: Double = 0, eastMeters: Double = 0, at t: TimeInterval,
                       accuracy: Double = 5, speed: Double? = nil, speedAccuracy: Double? = 0.5) -> LocationSample {
        let lat = lat0 + northMeters / metersPerDegreeLat
        let lon = lon0 + eastMeters / (metersPerDegreeLat * cos(lat0 * .pi / 180))
        return LocationSample(timestamp: t0.addingTimeInterval(t), latitude: lat, longitude: lon,
                              horizontalAccuracy: accuracy, speed: speed,
                              speedAccuracy: speed == nil ? nil : speedAccuracy)
    }

    /// A straight northbound track at constant speed, one fix per second.
    static func line(seconds: Int, speed: Double, startTime: TimeInterval = 0, startNorth: Double = 0,
                     accuracy: Double = 5, reportSpeed: Bool = true) -> [LocationSample] {
        (0...seconds).map { i in
            sample(northMeters: startNorth + Double(i) * speed, at: startTime + Double(i), accuracy: accuracy,
                   speed: reportSpeed ? speed : nil)
        }
    }

    /// Feeds samples into the recorder, each "arriving" 0.2 s after its timestamp.
    static func feed(_ samples: [LocationSample], into r: inout RideRecorder) -> [FilterDecision] {
        samples.map { r.ingest($0, now: $0.timestamp.addingTimeInterval(0.2)) }
    }
}
