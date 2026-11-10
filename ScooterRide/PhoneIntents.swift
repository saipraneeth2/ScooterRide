import AppIntents

/// "End my scooter ride in ScooterRide" from iPhone. Works only when the watch app is
/// reachable right now; otherwise it says so instead of queueing a late request.
struct EndScooterRideIntent: AppIntent {
    static var title: LocalizedStringResource = "End Scooter Ride"
    static var description = IntentDescription("Ends and saves the scooter ride in progress on Apple Watch, when the watch is reachable.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await RideLibrary.shared.sync.requestEndRideOnWatch()
        return .result(dialog: "\(text)")
    }
}

struct ScooterRidePhoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: EndScooterRideIntent(),
                    phrases: ["End my scooter ride in \(.applicationName)",
                              "Stop \(.applicationName)"],
                    shortTitle: "End Ride",
                    systemImageName: "stop.circle")
    }
}
