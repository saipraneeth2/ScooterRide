import SwiftUI
import RideKit

struct StartView: View {
    @Environment(RideViewModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let reason = model.smart.startSuggestion { startSuggestion(reason) }

                Button {
                    model.startRide()
                } label: {
                    Label("Start Ride", systemImage: "scooter")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityHint("Starts recording a scooter ride with GPS")

                if let message = model.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                if let recovered = model.recoveredRide {
                    VStack(spacing: 4) {
                        Text("Recovered an unfinished ride")
                            .font(.footnote.weight(.semibold))
                        Text("\(RideFormat.distance(recovered.distanceMeters)) · ended at its last GPS fix")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("OK") { model.dismissRecoveredRide() }
                            .controlSize(.small)
                    }
                    .padding(8)
                    .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }

                locationRow

                NavigationLink {
                    RecentRidesView()
                } label: {
                    Label("Rides (\(model.recentRides.count))", systemImage: "list.bullet")
                }

                Toggle("Precise GPS", isOn: Binding(get: { model.highAccuracyGPS },
                                                    set: { model.setHighAccuracy($0) }))
                    .font(.footnote)

                Toggle("Smart Detection", isOn: Binding(get: { model.smart.isEnabled },
                                                        set: { model.smart.setEnabled($0) }))
                    .font(.footnote)
                if model.smart.isEnabled {
                    Text("Suggests starting or ending a ride, but never does either by itself. Results are estimates.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    BluetoothDiscoveryList(scanner: model.smart.scanner, chosenID: model.smart.myScooterID,
                                           chosenLabel: model.smart.myScooterLabel,
                                           onChoose: { model.smart.chooseScooter($0) },
                                           onForget: { model.smart.forgetScooter() })
                } label: {
                    Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                }

                Text("Speeds are GPS estimates. Rides are never saved as workouts and earn no exercise minutes or calories.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("ScooterRide")
    }

    private func startSuggestion(_ reason: StartReason) -> some View {
        VStack(spacing: 6) {
            Text(suggestionText(reason))
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Smart Detection estimate")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Button("Start") { model.startRide() }
                    .tint(.green)
                Button("Not now") { model.smart.dismissStartSuggestion() }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private func suggestionText(_ reason: StartReason) -> String {
        switch reason {
        case .movingAtScooterSpeed(let speed):
            return "Moving at about \(RideFormat.speed(speed)) mph. Start a ride?"
        case .scooterNearby:
            return "Your scooter seems to be on nearby. Start a ride?"
        }
    }

    @ViewBuilder private var locationRow: some View {
        switch model.authorization {
        case .notDetermined:
            Label("Location will be requested on Start", systemImage: "location")
                .font(.caption2).foregroundStyle(.secondary)
        case .denied, .restricted:
            Label("Location access is off", systemImage: "location.slash")
                .font(.caption2).foregroundStyle(.orange)
        default:
            Label(model.backgroundUpdatesAvailable ? "Location ready" : "Location ready (foreground only)",
                  systemImage: "location.fill")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
