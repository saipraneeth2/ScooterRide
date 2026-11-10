import MapKit
import UIKit
import RideKit

extension Coordinate {
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension RouteRegion {
    var mk: MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude),
                           span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }
}

/// Small static map images with the route drawn on top, for the ride list. Cached in memory.
/// Map tiles come from Apple Maps; ride data itself never leaves the device.
@MainActor
final class RouteSnapshotter {
    static let shared = RouteSnapshotter()
    private let cache = NSCache<NSString, UIImage>()

    func image(for ride: RideSession, size: CGSize, style: UIUserInterfaceStyle) async -> UIImage? {
        let key = "\(ride.id.uuidString)-\(Int(size.width))x\(Int(size.height))-\(style.rawValue)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let region = RouteGeometry.region(for: ride.route) else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = region.mk
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: style)
        options.pointOfInterestFilter = .excludingAll

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            snapshot.image.draw(at: .zero)
            let path = UIBezierPath()
            for segment in RouteGeometry.segments(of: ride.route) {
                for (i, c) in RouteGeometry.simplify(segment, maxPoints: 300).enumerated() {
                    let p = snapshot.point(for: c.cl)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
            }
            path.lineWidth = 3
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.systemGreen.setStroke()
            path.stroke()
        }
        cache.setObject(image, forKey: key)
        return image
    }
}
