import SwiftUI
import RideKit

struct AboutView: View {
    @Environment(RideLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var alerts = RidingAlerts.shared
    @State private var scanner = BluetoothScanner()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Ride-type labels", isOn: Binding(get: { library.showRideTypes },
                                                             set: { library.setShowRideTypes($0) }))
                    Text("Labels each ride as scooter-like, mostly walking, or faster than an E3 Pro, from GPS speed and (if the watch recorded it) motion activity. \(RideTypeEstimate.caveat)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("Riding alerts", isOn: Binding(get: { alerts.isEnabled }, set: { alerts.setEnabled($0) }))
                    Text("When iOS notices you've moved about 500 m, ScooterRide checks your iPhone's recent motion. If it looks like riding, you get a notification suggesting a ride on Apple Watch. Needs “Always” location. It never records a ride by itself, can't start the watch app, and may misfire on a bike or bus.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if alerts.isEnabled {
                        LabeledContent("Status", value: alerts.statusText)
                        if let check = alerts.lastCheck { LabeledContent("Last check", value: check) }
                    }
                } header: {
                    Text("Smart Detection")
                } footer: {
                    Text("Smart Detection on Apple Watch has its own switch in the watch app. Everything here is an estimate and only suggests.")
                }

                Section("Bluetooth") {
                    NavigationLink {
                        BluetoothDiscoveryList(scanner: scanner)
                    } label: {
                        Label("Nearby Bluetooth devices", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }

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
                    Label("Never changes your scooter. Connects only when you tap Read standard info", systemImage: "scooter")
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
