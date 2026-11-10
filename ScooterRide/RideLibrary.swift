import Foundation
import Observation
import RideKit

/// The iPhone's ride history: rides synced from Apple Watch, stored locally.
@MainActor
@Observable
final class RideLibrary {
    static let shared = RideLibrary()

    private(set) var rides: [RideSession] = []
    private(set) var unreadableCount = 0
    private(set) var watchStatus = "Connecting to Apple Watch…"
    var errorMessage: String?

    @ObservationIgnored let sync: PhoneSync
    @ObservationIgnored private let store: RideStore?

    init() {
        store = try? RideStore(directory: RideStore.defaultDirectory())
        sync = PhoneSync(store: store)
        if store == nil { errorMessage = "Ride storage is unavailable." }
        sync.onChange = { [weak self] in self?.reload() }
        sync.activate()
        reload()
    }

    func reload() {
        let result = store?.all()
        rides = result?.rides ?? []
        unreadableCount = result?.unreadable.count ?? 0
        watchStatus = sync.statusText
        if let e = sync.lastError { errorMessage = e }
    }

    func ride(id: UUID) -> RideSession? { rides.first { $0.id == id } }

    /// Deletes from iPhone and asks Apple Watch to delete its copy too.
    func delete(_ ride: RideSession) {
        do {
            try sync.deleteRide(ride.id)
        } catch {
            errorMessage = "Could not delete the ride: \(error.localizedDescription)"
        }
        reload()
    }
}
