import SwiftUI
import MapKit
import RideKit

struct RideDetailView: View {
    let ride: RideSession
    @Environment(RideLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var end: Date { ride.endDate ?? Date() }

    var body: some View {
        List {
            Section {
                RideMap(ride: ride)
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
            }

            Section("Summary") {
                LabeledContent("Ride time", value: RideFormat.duration(ride.activeDuration(at: end)))
                LabeledContent("Distance", value: RideFormat.distance(ride.distanceMeters))
                LabeledContent("Average speed", value: "\(RideFormat.speed(ride.averageSpeed(at: end))) mph")
                LabeledContent("Max speed", value: "\(RideFormat.speed(ride.maxSpeedMetersPerSecond)) mph")
                LabeledContent("Started", value: ride.startDate.formatted(date: .omitted, time: .shortened))
                LabeledContent("Ended", value: end.formatted(date: .omitted, time: .shortened))
                if ride.intervals.count > 1 {
                    LabeledContent("Pauses", value: "\(ride.intervals.count - 1)")
                }
            }

            Section {
                LabeledContent("Fixes kept", value: "\(ride.acceptedSampleCount)")
                LabeledContent("Fixes filtered out", value: "\(ride.rejectedSampleTotal)")
                ForEach(ride.rejectedSampleCounts.sorted { $0.value > $1.value }, id: \.key) { reason, count in
                    LabeledContent(reasonText(reason), value: "\(count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if ride.recovered {
                    Label("Recovered after the watch app was closed mid-ride; ended at its last GPS fix.",
                          systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                }
            } header: {
                Text("GPS")
            } footer: {
                Text("Speeds and distance are GPS estimates and can differ from the scooter's speedometer. This ride is not a workout and adds no exercise minutes or calories.")
            }

            if library.showRideTypes {
                let estimate = RideTypeEstimator.estimate(ride)
                Section {
                    Text(estimate.title).font(.headline)
                    ForEach(estimate.details, id: \.self) { Text($0).font(.footnote) }
                } header: {
                    Text("Ride type (estimate)")
                } footer: {
                    Text(RideTypeEstimate.caveat)
                }
            }

            Section {
                Button("Delete Ride", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(ride.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this ride?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete from iPhone and Apple Watch", role: .destructive) {
                library.delete(ride)
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func reasonText(_ r: RejectionReason) -> String {
        switch r {
        case .notRecording: return "While paused"
        case .invalidCoordinate: return "Invalid position"
        case .poorAccuracy: return "Poor accuracy"
        case .stale: return "Too old"
        case .outOfOrder: return "Out of order"
        case .duplicate: return "Duplicate"
        case .implausibleSpeed: return "Implausible speed"
        case .implausibleJump: return "Implausible jump"
        case .beforeSegmentStart: return "Before start"
        }
    }
}

struct RideMap: View {
    let ride: RideSession

    var body: some View {
        let segments = RouteGeometry.segments(of: ride.route)
        if let region = RouteGeometry.region(for: ride.route) {
            Map(initialPosition: .region(region.mk)) {
                ForEach(segments.indices, id: \.self) { i in
                    MapPolyline(coordinates: RouteGeometry.simplify(segments[i], maxPoints: 2000).map(\.cl))
                        .stroke(.green, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                if let start = segments.first?.first {
                    Marker("Start", systemImage: "flag.fill", coordinate: start.cl).tint(.green)
                }
                if let finish = segments.last?.last {
                    Marker("End", systemImage: "flag.checkered", coordinate: finish.cl).tint(.red)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
        } else {
            ContentUnavailableView("No GPS route", systemImage: "location.slash",
                                   description: Text("No reliable GPS fixes were recorded for this ride."))
        }
    }
}
