import SwiftUI
import RideKit

struct RideSummaryView: View {
    let ride: RideSession
    var showsDone: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(RideViewModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(ride.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if ride.recovered {
                    Label("Recovered after the app was closed", systemImage: "arrow.uturn.backward")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        MetricTile(title: "TIME", value: RideFormat.duration(ride.activeDuration(at: ride.endDate ?? Date())))
                        MetricTile(title: "DIST", value: RideFormat.distance(ride.distanceMeters))
                    }
                    GridRow {
                        MetricTile(title: "AVG MPH", value: RideFormat.speed(ride.averageSpeed(at: ride.endDate ?? Date())))
                        MetricTile(title: "MAX MPH", value: RideFormat.speed(ride.maxSpeedMetersPerSecond))
                    }
                }
                Text("GPS fixes: \(ride.acceptedSampleCount) kept, \(ride.rejectedSampleTotal) filtered out")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if model.smart.isEnabled {
                    let estimate = RideTypeEstimator.estimate(ride)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(estimate.title).font(.footnote.weight(.semibold))
                        Text("Ride type estimate").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("Speeds are GPS estimates. Not saved as a workout.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if showsDone {
                    Button("Done") { dismiss() }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Ride")
    }
}
