import Foundation
import Observation
import CoreLocation
import RideKit

/// Owns the ride lifecycle on the watch: user actions -> RideRecorder, GPS -> RideRecorder,
/// finished rides -> RideStore. No HealthKit: rides never become workouts.
@MainActor
@Observable
final class RideViewModel {
    private(set) var recorder = RideRecorder()
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var recentRides: [RideSession] = []
    private(set) var recoveredRide: RideSession?
    private(set) var highAccuracyGPS = true
    var lastFinishedRide: RideSession?
    var errorMessage: String?

    let backgroundUpdatesAvailable = LocationService.supportsBackgroundUpdates

    @ObservationIgnored private let location = LocationService()
    @ObservationIgnored private let store: RideStore?
    @ObservationIgnored private var lastCheckpoint = Date.distantPast
    @ObservationIgnored private var pendingStart = false

    static let accuracyKey = "highAccuracyGPS"
    /// How often the in-progress ride is written to disk while recording.
    static let checkpointInterval: TimeInterval = 30

    init() {
        store = try? RideStore(directory: RideStore.defaultDirectory())
        if UserDefaults.standard.object(forKey: Self.accuracyKey) != nil {
            highAccuracyGPS = UserDefaults.standard.bool(forKey: Self.accuracyKey)
        }
        authorization = location.authorizationStatus
        location.onEvent = { [weak self] event in self?.handle(event) }
        if store == nil { errorMessage = "Ride storage is unavailable; rides cannot be saved." }
        // A checkpoint left behind means the app was terminated mid-ride: keep that ride.
        recoveredRide = try? store?.recoverCheckpoint()
        reloadRides()
    }

    // MARK: Ride controls

    func startRide() {
        errorMessage = nil
        recoveredRide = nil
        switch location.authorizationStatus {
        case .notDetermined:
            pendingStart = true
            location.requestAuthorization()
        case .denied, .restricted:
            errorMessage = "ScooterRide needs location access to measure speed and distance. On Apple Watch: Settings > Privacy & Security > Location Services > ScooterRide."
        default:
            beginRecording()
        }
    }

    func pause() {
        guard recorder.state == .active else { return }
        try? recorder.pause(at: Date())
        location.stop()            // saves battery; GPS re-acquires on resume
        checkpoint(force: true)
    }

    func resume() {
        guard recorder.state == .paused else { return }
        try? recorder.resume(at: Date())
        location.start(highAccuracy: highAccuracyGPS)
        checkpoint(force: true)
    }

    func endRide() {
        guard let ride = try? recorder.end(at: Date()) else { return }
        location.stop()
        do {
            try store?.save(ride)
            store?.clearCheckpoint()
        } catch {
            errorMessage = "Could not save the ride (\(error.localizedDescription)). It is kept as a checkpoint and recovered on next launch."
        }
        lastFinishedRide = ride
        recorder.reset()
        reloadRides()
    }

    func discardRide() {
        location.stop()
        store?.clearCheckpoint()
        recorder.reset()
    }

    func setHighAccuracy(_ on: Bool) {
        highAccuracyGPS = on
        UserDefaults.standard.set(on, forKey: Self.accuracyKey)
        if recorder.state == .active { location.start(highAccuracy: on) }
    }

    func dismissRecoveredRide() { recoveredRide = nil }

    func metrics(at date: Date) -> RideMetrics { recorder.metrics(at: date) }

    /// Called when the app leaves the foreground: persist progress in case watchOS terminates it.
    func appMovedToBackground() { checkpoint(force: true) }

    func reloadRides() { recentRides = store?.all().rides ?? [] }

    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }

    // MARK: Private

    private func beginRecording() {
        do {
            try recorder.start(at: Date(), source: .watch)
        } catch {
            errorMessage = "Could not start a ride: \(error)"
            return
        }
        location.start(highAccuracy: highAccuracyGPS)
        checkpoint(force: true)
    }

    private func handle(_ event: LocationService.Event) {
        switch event {
        case .sample(let sample):
            if recorder.ingest(sample, now: Date()) == .accept { checkpoint(force: false) }
        case .authorization(let status):
            authorization = status
            if pendingStart {
                pendingStart = false
                if isAuthorized { beginRecording() }
                else if status != .notDetermined {
                    errorMessage = "Location access was not allowed, so a ride cannot be recorded."
                }
            } else if recorder.state == .active, status == .denied || status == .restricted {
                pause()
                errorMessage = "Location access was turned off. The ride is paused."
            }
        case .failure(let message):
            errorMessage = message
        }
    }

    private func checkpoint(force: Bool) {
        guard let session = recorder.session, recorder.state == .active || recorder.state == .paused else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastCheckpoint) >= Self.checkpointInterval else { return }
        do {
            try store?.saveCheckpoint(session)
            lastCheckpoint = now
        } catch {
            errorMessage = "Could not save ride progress: \(error.localizedDescription)"
        }
    }
}
