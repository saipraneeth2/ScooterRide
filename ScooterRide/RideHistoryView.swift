import SwiftUI
import RideKit

struct RideHistoryView: View {
    @Environment(RideLibrary.self) private var library
    @State private var showAbout = false
    @State private var rideToDelete: RideSession?

    var body: some View {
        NavigationStack {
            Group {
                if library.rides.isEmpty {
                    ContentUnavailableView {
                        Label("No rides yet", systemImage: "scooter")
                    } description: {
                        Text("Record a ride with ScooterRide on Apple Watch. It appears here after the watch syncs, which needs the watch near this iPhone.")
                    }
                } else {
                    List {
                        Section {
                            ForEach(library.rides) { ride in
                                NavigationLink(value: ride.id) { RideRow(ride: ride) }
                                    .swipeActions {
                                        Button("Delete", systemImage: "trash", role: .destructive) { rideToDelete = ride }
                                    }
                            }
                        } footer: {
                            Text("\(library.watchStatus) Speeds are GPS estimates.")
                        }
                    }
                }
            }
            .navigationTitle("Scooter Rides")
            .navigationDestination(for: UUID.self) { id in
                if let ride = library.ride(id: id) {
                    RideDetailView(ride: ride)
                } else {
                    ContentUnavailableView("Ride deleted", systemImage: "trash")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAbout = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About ScooterRide")
                }
            }
            .refreshable { library.reload() }
            .sheet(isPresented: $showAbout) { AboutView() }
            .confirmationDialog("Delete this ride?", isPresented: Binding(get: { rideToDelete != nil },
                                                                           set: { if !$0 { rideToDelete = nil } }),
                                titleVisibility: .visible, presenting: rideToDelete) { ride in
                Button("Delete from iPhone and Apple Watch", role: .destructive) { library.delete(ride) }
            } message: { _ in
                Text("This can't be undone.")
            }
            .alert("ScooterRide", isPresented: Binding(get: { library.errorMessage != nil },
                                                       set: { if !$0 { library.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.errorMessage ?? "")
            }
        }
    }
}

struct RideRow: View {
    let ride: RideSession

    var body: some View {
        HStack(spacing: 12) {
            RouteThumbnail(ride: ride)
            VStack(alignment: .leading, spacing: 3) {
                Text(ride.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Text("\(RideFormat.distance(ride.distanceMeters)) · \(RideFormat.duration(ride.activeDuration(at: ride.endDate ?? Date())))")
                    .font(.subheadline)
                Text("Max \(RideFormat.speed(ride.maxSpeedMetersPerSecond)) mph · Avg \(RideFormat.speed(ride.averageSpeed(at: ride.endDate ?? Date()))) mph")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RouteThumbnail: View {
    let ride: RideSession
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                Image(systemName: ride.route.isEmpty ? "location.slash" : "map")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: "\(ride.id)-\(colorScheme == .dark)") {
            image = await RouteSnapshotter.shared.image(for: ride, size: CGSize(width: 64, height: 64),
                                                        style: colorScheme == .dark ? .dark : .light)
        }
        .accessibilityHidden(true)
    }
}
