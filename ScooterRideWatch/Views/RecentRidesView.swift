import SwiftUI
import RideKit

struct RecentRidesView: View {
    @Environment(RideViewModel.self) private var model

    var body: some View {
        Group {
            if model.recentRides.isEmpty {
                Text("No rides yet. Rides you record appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                List(model.recentRides) { ride in
                    NavigationLink {
                        RideSummaryView(ride: ride)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ride.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote.weight(.semibold))
                            Text("\(RideFormat.distance(ride.distanceMeters)) · \(RideFormat.duration(ride.activeDuration(at: ride.endDate ?? Date())))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Label(model.syncedRideIDs.contains(ride.id) ? "On iPhone" : "Waiting for iPhone",
                                  systemImage: model.syncedRideIDs.contains(ride.id) ? "checkmark.icloud" : "clock")
                                .font(.caption2)
                                .foregroundStyle(model.syncedRideIDs.contains(ride.id) ? .green : .secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Rides")
        .onAppear { model.reloadRides() }
    }
}
