import SwiftUI
import RideKit

struct StartView: View {
    @Environment(RideViewModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
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

                Text("Speeds are GPS estimates. Rides are never saved as workouts and earn no exercise minutes or calories.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("ScooterRide")
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
