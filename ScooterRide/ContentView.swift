import SwiftUI
import RideKit

/// Phase 1 companion. Rides are recorded and stored on Apple Watch; Phase 2 adds
/// WatchConnectivity sync, ride history, map previews and deletion here.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Open ScooterRide on Apple Watch and tap Start Ride.", systemImage: "applewatch")
                    Label("Rides are stored on the watch for now. Ride history on iPhone arrives in the next update.",
                          systemImage: "clock.arrow.circlepath")
                } header: {
                    Text("Recording rides")
                }

                Section {
                    Text("ScooterRide cannot change how Apple Watch detects workouts. If your watch suggests Outdoor Cycling while you ride, you can turn that prompt off yourself: Watch app on iPhone > Workout > Start Workout Reminder. This turns off start reminders for every workout type, not just cycling.")
                        .font(.callout)
                } header: {
                    Text("Outdoor Cycling prompts")
                }

                Section {
                    Label("Rides are never saved as workouts", systemImage: "heart.slash")
                    Label("No exercise minutes or calories are added", systemImage: "flame")
                    Label("No account, no servers, no cloud", systemImage: "icloud.slash")
                    Label("Speeds are GPS estimates, not scooter readings", systemImage: "location")
                } header: {
                    Text("What ScooterRide never does")
                }
            }
            .navigationTitle("ScooterRide")
        }
    }
}

#Preview {
    ContentView()
}
