import SwiftUI

struct AboutView: View {
    @Environment(RideLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Apple Watch") {
                    Label(library.watchStatus, systemImage: "applewatch")
                    Text("Rides are recorded on Apple Watch and copied here automatically. If the watch is away from this iPhone, rides wait on the watch and sync later.")
                        .font(.callout)
                }

                Section("Siri and Shortcuts") {
                    Text("On Apple Watch: “Start a scooter ride in ScooterRide” and “End my scooter ride in ScooterRide”. Start opens the app, because GPS permission needs it on screen.")
                    Text("On iPhone: “End my scooter ride in ScooterRide” works when the watch app is reachable. iPhone can't start a ride on the watch in the background, so start rides on the watch.")
                    Text("On Apple Watch Ultra you can set the Action button to run the Start Ride shortcut (Settings > Action Button > Shortcut).")
                }
                .font(.callout)

                Section("Outdoor Cycling prompts") {
                    Text("ScooterRide cannot change how Apple Watch detects workouts. If your watch suggests Outdoor Cycling while you ride, you can turn that prompt off yourself: Watch app on iPhone > Workout > Start Workout Reminder. This turns off start reminders for every workout type.")
                        .font(.callout)
                }

                Section("What ScooterRide never does") {
                    Label("Rides are never saved as workouts", systemImage: "heart.slash")
                    Label("No exercise minutes or calories are added", systemImage: "flame")
                    Label("No account, no servers; rides stay on your devices", systemImage: "icloud.slash")
                    Label("Speeds are GPS estimates, not scooter readings", systemImage: "location")
                    Label("Never connects to or changes your scooter", systemImage: "scooter")
                }

                if library.unreadableCount > 0 {
                    Section {
                        Label("\(library.unreadableCount) ride file(s) could not be read and are hidden.",
                              systemImage: "exclamationmark.triangle")
                    }
                }
            }
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
