import AppIntents
import RideKit

/// "Start a scooter ride in ScooterRide". Opens the app (location permission and GPS need
/// the app in the foreground), then starts recording. Usable from Siri, the Shortcuts app,
/// and on Apple Watch Ultra, an Action button set to run a shortcut.
struct StartScooterRideIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Scooter Ride"
    static var description = IntentDescription("Starts recording a scooter ride with GPS on Apple Watch. It is not a workout.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = RideViewModel.shared
        switch model.recorder.state {
        case .active, .paused:
            return .result(dialog: "A scooter ride is already in progress.")
        case .idle, .ended:
            model.startRide()
            if model.recorder.state == .active {
                return .result(dialog: "Scooter ride started.")
            }
            let reason = model.errorMessage ?? "Allow location access in ScooterRide, then try again."
            return .result(dialog: "\(reason)")
        }
    }
}

/// "End my scooter ride in ScooterRide". Ends and saves the ride in progress.
struct EndScooterRideIntent: AppIntent {
    static var title: LocalizedStringResource = "End Scooter Ride"
    static var description = IntentDescription("Ends and saves the scooter ride in progress on Apple Watch.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = RideViewModel.shared
        guard model.recorder.state == .active || model.recorder.state == .paused else {
            return .result(dialog: "No scooter ride is in progress.")
        }
        model.endRide()
        if let ride = model.lastFinishedRide {
            let summary = "\(RideFormat.distance(ride.distanceMeters)) in \(RideFormat.duration(ride.activeDuration(at: ride.endDate ?? Date())))"
            return .result(dialog: "Scooter ride saved: \(summary).")
        }
        return .result(dialog: "Scooter ride ended.")
    }
}

struct ScooterRideWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartScooterRideIntent(),
                    phrases: ["Start a scooter ride in \(.applicationName)",
                              "Start \(.applicationName)"],
                    shortTitle: "Start Ride",
                    systemImageName: "scooter")
        AppShortcut(intent: EndScooterRideIntent(),
                    phrases: ["End my scooter ride in \(.applicationName)",
                              "Stop \(.applicationName)"],
                    shortTitle: "End Ride",
                    systemImageName: "stop.circle")
    }
}
