import Foundation
import Observation
import CoreLocation
import CoreMotion
import UserNotifications
import WatchKit
import RideKit

/// Optional Smart Detection on the watch. Off by default. It only suggests; the rider decides.
///
/// - During a ride: Core Motion activity is added to the ride (for the ride-type estimate), and
///   a sustained stop raises an "End ride?" suggestion: an alert in the app, or a notification
///   when the wrist is down.
/// - While the app is open and not recording: GPS speed, and Bluetooth sightings of the scooter
///   the rider picked, can raise a "Start ride?" suggestion. Nothing runs in the background then.
@MainActor
@Observable
final class SmartDetection: NSObject {
    static let enabledKey = "smartDetectionEnabled"
    static let scooterIDKey = "myScooterID"
    static let scooterLabelKey = "myScooterLabel"
    static let stopCategory = "RIDE_STOP_SUGGESTION"
    static let endAction = "END_AND_SAVE"
    static let keepAction = "KEEP_RIDING"

    private(set) var isEnabled = UserDefaults.standard.bool(forKey: SmartDetection.enabledKey)
    private(set) var myScooterID: UUID? = UserDefaults.standard.string(forKey: SmartDetection.scooterIDKey).flatMap(UUID.init)
    /// Masked name only (never the full advertised name, which may be a serial number).
    private(set) var myScooterLabel: String? = UserDefaults.standard.string(forKey: SmartDetection.scooterLabelKey)
    private(set) var startSuggestion: StartReason?
    private(set) var stopSuggestionPending = false
    private(set) var latestMotion: MotionKind?
    let motionAvailable = CMMotionActivityManager.isActivityAvailable()
    let scanner = BluetoothScanner()

    /// Motion changes during a ride, for the recorder.
    @ObservationIgnored var onMotion: ((MotionKind, Date) -> Void)?
    /// The ride's current smoothed GPS speed, nil when stale.
    @ObservationIgnored var currentRideSpeed: (() -> Double?)?
    /// The rider chose End & Save from the stop notification.
    @ObservationIgnored var onEndRequested: (() -> Void)?

    @ObservationIgnored private let motion = CMMotionActivityManager()
    @ObservationIgnored private let idleLocation = CLLocationManager()
    @ObservationIgnored private var stopDetector = StopDetector()
    @ObservationIgnored private var startDetector = StartDetector()
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var rideActive = false
    @ObservationIgnored private var rideRunning = false   // active, not paused
    @ObservationIgnored private var appActive = false
    @ObservationIgnored private var idleWatching = false

    override init() {
        super.init()
        idleLocation.delegate = self
        idleLocation.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        idleLocation.activityType = .otherNavigation
        UNUserNotificationCenter.current().delegate = self
        let end = UNNotificationAction(identifier: Self.endAction, title: "End & Save", options: [.foreground])
        let keep = UNNotificationAction(identifier: Self.keepAction, title: "Keep Riding", options: [])
        UNUserNotificationCenter.current().setNotificationCategories(
            [UNNotificationCategory(identifier: Self.stopCategory, actions: [end, keep], intentIdentifiers: [])])
        scanner.onSighting = { [weak self] device in self?.sighted(device) }
    }

    // MARK: Settings

    func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            // Ask for permissions now, while the rider is looking at the switch, not mid-ride.
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            if motionAvailable {
                let now = Date()
                motion.queryActivityStarting(from: now.addingTimeInterval(-60), to: now, to: .main) { _, _ in }
            }
            if rideActive {
                startMotionUpdates()
                startHeartbeat()
            }
            refreshIdleWatch()
        } else {
            heartbeat?.cancel()
            heartbeat = nil
            stopMotionUpdates()
            endIdleWatch()
            clearStopSuggestion()
            startSuggestion = nil
        }
    }

    func chooseScooter(_ device: DiscoveredDevice) {
        myScooterID = device.id
        myScooterLabel = device.displayName
        UserDefaults.standard.set(device.id.uuidString, forKey: Self.scooterIDKey)
        UserDefaults.standard.set(device.displayName, forKey: Self.scooterLabelKey)
    }

    func forgetScooter() {
        myScooterID = nil
        myScooterLabel = nil
        UserDefaults.standard.removeObject(forKey: Self.scooterIDKey)
        UserDefaults.standard.removeObject(forKey: Self.scooterLabelKey)
    }

    // MARK: Ride lifecycle (called by RideViewModel)

    func rideStarted() {
        rideActive = true
        rideRunning = true
        stopDetector.reset()
        clearStopSuggestion()
        startSuggestion = nil
        endIdleWatch()
        guard isEnabled else { return }
        startMotionUpdates()
        startHeartbeat()
    }

    func ridePaused() {
        rideRunning = false
        stopDetector.reset()
        clearStopSuggestion()
    }

    func rideResumed() {
        rideRunning = true
        stopDetector.reset()
    }

    func rideEnded() {
        rideActive = false
        rideRunning = false
        heartbeat?.cancel()
        heartbeat = nil
        stopMotionUpdates()
        stopDetector.reset()
        clearStopSuggestion()
        refreshIdleWatch()
    }

    /// Called for each accepted GPS fix during a ride.
    func rideReading(at time: Date) {
        guard isEnabled, rideRunning else { return }
        evaluateStop(at: time)
    }

    func keepRiding() {
        stopDetector.dismiss(at: Date())
        clearStopSuggestion()
    }

    func dismissStartSuggestion() {
        startDetector.dismiss(at: Date())
        startSuggestion = nil
    }

    // MARK: App lifecycle

    func appBecameActive() {
        appActive = true
        refreshIdleWatch()
    }

    func appMovedToBackground() {
        appActive = false
        endIdleWatch()
    }

    // MARK: Stop suggestion

    private func startHeartbeat() {
        heartbeat?.cancel()
        // GPS may go quiet when the rider walks indoors; check every 20 s so motion can still
        // provide evidence. Runs only during a ride with Smart Detection on.
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.isEnabled, self.rideRunning { self.evaluateStop(at: Date()) }
            }
        }
    }

    private func evaluateStop(at time: Date) {
        guard !stopSuggestionPending else { return }
        if stopDetector.update(speed: currentRideSpeed?(), motion: latestMotion, at: time) {
            stopSuggestionPending = true
            WKInterfaceDevice.current().play(.notification)
            if !appActive { postStopNotification() }
        }
    }

    private func postStopNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Stopped riding?"
        content.body = "No riding movement for 3 minutes (estimate). End and save this ride?"
        content.categoryIdentifier = Self.stopCategory
        content.sound = .default
        let request = UNNotificationRequest(identifier: Self.stopCategory, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func clearStopSuggestion() {
        stopSuggestionPending = false
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.stopCategory])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.stopCategory])
    }

    // MARK: Motion

    private func startMotionUpdates() {
        guard motionAvailable, CMMotionActivityManager.authorizationStatus() != .denied else { return }
        motion.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            let kind = MotionKind(activity)
            let date = activity.startDate
            MainActor.assumeIsolated {
                guard let self else { return }
                self.latestMotion = kind
                self.onMotion?(kind, date)
            }
        }
    }

    private func stopMotionUpdates() {
        motion.stopActivityUpdates()
        latestMotion = nil
    }

    // MARK: Start suggestion (app open, idle)

    private func refreshIdleWatch() {
        if isEnabled, appActive, !rideActive { beginIdleWatch() } else { endIdleWatch() }
    }

    private func beginIdleWatch() {
        guard !idleWatching else { return }
        idleWatching = true
        startDetector.reset()
        let status = idleLocation.authorizationStatus
        // Never prompts from here: location permission is asked when the rider taps Start.
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            idleLocation.startUpdatingLocation()
        }
        // One short scan per app opening, only if the rider picked their scooter.
        if myScooterID != nil { scanner.startScan(duration: 15) }
    }

    private func endIdleWatch() {
        guard idleWatching else { return }
        idleWatching = false
        idleLocation.stopUpdatingLocation()
        scanner.stopScan()
    }

    private func sighted(_ device: DiscoveredDevice) {
        guard idleWatching, isEnabled, device.id == myScooterID,
              let reason = startDetector.scooterSeen(rssi: device.rssi, at: Date()) else { return }
        offerStart(reason)
    }

    private func offerStart(_ reason: StartReason) {
        startSuggestion = reason
        WKInterfaceDevice.current().play(.click)
    }
}

extension SmartDetection: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map(LocationSample.init(clLocation:))
        MainActor.assumeIsolated {
            guard self.idleWatching, self.isEnabled else { return }
            for s in samples {
                if let reason = self.startDetector.update(s, at: Date()) { self.offerStart(reason) }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension SmartDetection: UNUserNotificationCenterDelegate {
    /// In the app, the alert on screen handles the suggestion, so no banner.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        Task { @MainActor in
            if category == Self.stopCategory {
                switch action {
                case Self.endAction: self.onEndRequested?()
                case Self.keepAction: self.keepRiding()
                default: break   // opened the app: the in-app alert is still showing
                }
            }
            completionHandler()
        }
    }
}
