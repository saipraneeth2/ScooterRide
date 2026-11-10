import Foundation
import Observation
import CoreLocation
import CoreMotion
import UserNotifications
import UIKit
import RideKit

/// Optional iPhone riding alert (Smart Detection). Off by default.
///
/// iOS wakes the app for significant location changes (roughly every 500 m of movement, using
/// little power). Each time, the app looks at the iPhone's recent motion activity and, if it
/// looks like riding, sends a notification suggesting a ride on Apple Watch. It never starts
/// a ride: the watch can't be started from the iPhone in the background.
@MainActor
@Observable
final class RidingAlerts: NSObject {
    static let shared = RidingAlerts()
    static let enabledKey = "ridingAlertsEnabled"
    static let lastAlertKey = "ridingAlertsLastAlert"

    private(set) var isEnabled = UserDefaults.standard.bool(forKey: RidingAlerts.enabledKey)
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// The last decision, for the Settings screen ("why didn't it alert?").
    private(set) var lastCheck: String?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let motion = CMMotionActivityManager()
    @ObservationIgnored private let policy = RidingAlertPolicy()
    @ObservationIgnored private var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
    }

    /// Called at every launch, including the background relaunch iOS does for a significant
    /// location change, so that event reaches the delegate.
    func resumeIfEnabled() {
        if isEnabled { startMonitoring() }
    }

    func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        guard on else {
            manager.stopMonitoringSignificantLocationChanges()
            lastCheck = nil
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        if CMMotionActivityManager.isActivityAvailable() {
            let now = Date()   // a small query shows the Motion permission prompt now
            motion.queryActivityStarting(from: now.addingTimeInterval(-60), to: now, to: .main) { _, _ in }
        }
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
        startMonitoring()
    }

    var statusText: String {
        guard isEnabled else { return "Off" }
        switch authorization {
        case .authorizedAlways: return "On"
        case .authorizedWhenInUse:
            return "Needs “Always” location: Settings > Privacy & Security > Location Services > ScooterRide > Always."
        case .denied, .restricted: return "Location access is off for ScooterRide."
        default: return "Waiting for location permission."
        }
    }

    private func startMonitoring() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            lastCheck = "This iPhone can't monitor significant location changes."
            return
        }
        manager.startMonitoringSignificantLocationChanges()
    }

    private func evaluate(_ location: CLLocation) {
        let previous = lastLocation
        lastLocation = location
        let implied: Double? = previous.flatMap { previous in
            let dt = location.timestamp.timeIntervalSince(previous.timestamp)
            return dt >= 30 ? location.distance(from: previous) / dt : nil
        }
        guard CMMotionActivityManager.isActivityAvailable() else {
            lastCheck = "Motion activity isn't available on this iPhone."
            return
        }
        // Keep running long enough to finish, even when iOS woke the app in the background.
        let task = UIApplication.shared.beginBackgroundTask(withName: "RidingAlertCheck")
        let now = Date()
        motion.queryActivityStarting(from: now.addingTimeInterval(-policy.lookBack - 600), to: now, to: .main) { activities, error in
            let spans = (activities ?? []).map { MotionActivitySpan(start: $0.startDate, kind: MotionKind($0)) }
            let failed = error != nil
            MainActor.assumeIsolated {
                defer { UIApplication.shared.endBackgroundTask(task) }
                if failed {
                    self.lastCheck = "Couldn't read motion activity (is Motion & Fitness allowed?)."
                    return
                }
                let lastAlert = UserDefaults.standard.object(forKey: Self.lastAlertKey) as? Date
                let decision = self.policy.decide(activities: spans, now: now, lastAlert: lastAlert,
                                                  watchIsRecording: RideLibrary.shared.sync.watchIsRecording,
                                                  impliedSpeed: implied)
                let time = now.formatted(date: .omitted, time: .shortened)
                switch decision {
                case .alert:
                    UserDefaults.standard.set(now, forKey: Self.lastAlertKey)
                    self.postAlert()
                    self.lastCheck = "\(time): suggested a ride"
                case .skip(let reason):
                    self.lastCheck = "\(time): no alert (\(reason))"
                }
            }
        }
    }

    private func postAlert() {
        let content = UNMutableNotificationContent()
        content.title = "Riding your scooter?"
        content.body = "Your iPhone's motion looks like riding (estimate). Open ScooterRide on Apple Watch to record it."
        content.sound = .default
        content.categoryIdentifier = "RIDING_ALERT"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "ridingAlert", content: content, trigger: nil)) { _ in }
    }
}

extension RidingAlerts: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { self.authorization = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        MainActor.assumeIsolated {
            guard self.isEnabled else { return }
            self.evaluate(latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
