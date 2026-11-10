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
                        }
                    }
                }
            }
        }
        .navigationTitle("Rides")
        .onAppear { model.reloadRides() }
    }
}
