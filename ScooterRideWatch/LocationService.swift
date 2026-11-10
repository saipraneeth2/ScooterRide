import CoreLocation
import RideKit

/// Thin wrapper around CLLocationManager. All decisions about which fixes to keep
/// live in RideKit (LocationFilter / RideRecorder); this type only delivers fixes.
@MainActor
final class LocationService: NSObject {
    enum Event {
        case sample(LocationSample)
        case authorization(CLAuthorizationStatus)
        case failure(String)
    }

    var onEvent: ((Event) -> Void)?

    private let manager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private(set) var isUpdating = false

    override init() {
        super.init()
        manager.delegate = self
        // Non-automotive transportation; lets Core Location tune filtering for a vehicle.
        manager.activityType = .otherNavigation
        manager.distanceFilter = kCLDistanceFilterNone
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Background location requires the "location" background mode in Info.plist.
    /// Setting allowsBackgroundLocationUpdates without it is a fatal error, so we check
    /// the bundle first and fall back to foreground-only tracking.
    static var supportsBackgroundUpdates: Bool {
        ["UIBackgroundModes", "WKBackgroundModes"].contains { key in
            (Bundle.main.object(forInfoDictionaryKey: key) as? [String])?.contains("location") == true
        }
    }

    func start(highAccuracy: Bool) {
        manager.desiredAccuracy = highAccuracy ? kCLLocationAccuracyBest : kCLLocationAccuracyNearestTenMeters
        if Self.supportsBackgroundUpdates {
            manager.allowsBackgroundLocationUpdates = true
            if backgroundSession == nil {
                // Keeps the app's location use "in use" when the wrist is lowered (watchOS 10+).
                backgroundSession = CLBackgroundActivitySession()
            }
        }
        manager.startUpdatingLocation()
        isUpdating = true
    }

    func stop() {
        manager.stopUpdatingLocation()
        backgroundSession?.invalidate()
        backgroundSession = nil
        if Self.supportsBackgroundUpdates {
            manager.allowsBackgroundLocationUpdates = false
        }
        isUpdating = false
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map(LocationSample.init(clLocation:))
        MainActor.assumeIsolated {
            for s in samples { onEvent?(.sample(s)) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { onEvent?(.authorization(status)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message: String
        if let e = error as? CLError {
            switch e.code {
            case .locationUnknown:
                return   // transient: Core Location keeps trying
            case .denied:
                message = "Location access is off. On Apple Watch: Settings > Privacy & Security > Location Services > ScooterRide."
            default:
                message = "Location error: \(e.localizedDescription)"
            }
        } else {
            message = "Location error: \(error.localizedDescription)"
        }
        MainActor.assumeIsolated { onEvent?(.failure(message)) }
    }
}

extension LocationSample {
    /// Converts a CLLocation, mapping Core Location's negative "invalid" values to nil.
    init(clLocation l: CLLocation) {
        self.init(timestamp: l.timestamp,
                  latitude: l.coordinate.latitude,
                  longitude: l.coordinate.longitude,
                  altitude: l.verticalAccuracy >= 0 ? l.altitude : nil,
                  horizontalAccuracy: l.horizontalAccuracy,
                  speed: l.speed >= 0 ? l.speed : nil,
                  speedAccuracy: l.speedAccuracy >= 0 ? l.speedAccuracy : nil,
                  course: l.course >= 0 ? l.course : nil)
    }
}
