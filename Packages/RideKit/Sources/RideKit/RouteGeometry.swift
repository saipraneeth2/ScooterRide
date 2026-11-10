import Foundation

public struct Coordinate: Equatable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}

public struct RouteRegion: Equatable, Sendable {
    public var centerLatitude: Double
    public var centerLongitude: Double
    public var latitudeDelta: Double
    public var longitudeDelta: Double
}

/// Map helpers for drawing a recorded route. Pure, so they are unit-tested.
public enum RouteGeometry {
    /// The route split at pauses, so a map never draws a line across a paused stretch.
    public static func segments(of route: [RoutePoint]) -> [[Coordinate]] {
        var result: [[Coordinate]] = []
        var current: [Coordinate] = []
        var segment: Int?
        for p in route {
            if let s = segment, s != p.segment, !current.isEmpty {
                result.append(current)
                current = []
            }
            segment = p.segment
            current.append(Coordinate(latitude: p.sample.latitude, longitude: p.sample.longitude))
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// A region that contains the whole route with some padding. Nil for an empty route.
    public static func region(for route: [RoutePoint], padding: Double = 1.3,
                              minimumDelta: Double = 0.002) -> RouteRegion? {
        guard let first = route.first else { return nil }
        var minLat = first.sample.latitude, maxLat = minLat
        var minLon = first.sample.longitude, maxLon = minLon
        for p in route {
            minLat = min(minLat, p.sample.latitude); maxLat = max(maxLat, p.sample.latitude)
            minLon = min(minLon, p.sample.longitude); maxLon = max(maxLon, p.sample.longitude)
        }
        return RouteRegion(centerLatitude: (minLat + maxLat) / 2, centerLongitude: (minLon + maxLon) / 2,
                           latitudeDelta: max((maxLat - minLat) * padding, minimumDelta),
                           longitudeDelta: max((maxLon - minLon) * padding, minimumDelta))
    }

    /// Keeps at most `maxPoints` points (always the first and last) for fast drawing.
    public static func simplify(_ points: [Coordinate], maxPoints: Int) -> [Coordinate] {
        guard maxPoints >= 2, points.count > maxPoints else { return points }
        let step = Double(points.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { points[min(points.count - 1, Int((Double($0) * step).rounded()))] }
    }
}
