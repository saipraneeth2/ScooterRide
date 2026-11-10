import Foundation
import WatchConnectivity
import RideKit

/// Receives rides from Apple Watch, acknowledges them, propagates deletions, and can ask
/// a reachable watch to end the ride in progress.
@MainActor
final class PhoneSync: NSObject {
    var onChange: (() -> Void)?

    private(set) var state: SyncState
    private(set) var lastError: String?
    private let store: RideStore?
    private let stateStore: SyncStateStore?

    init(store: RideStore?) {
        self.store = store
        stateStore = store.map { SyncStateStore(directory: $0.directory) }
        state = stateStore?.load() ?? SyncState()
        super.init()
    }

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    var statusText: String {
        guard let session else { return "This iPhone doesn't support Apple Watch." }
        guard session.activationState == .activated else { return "Connecting to Apple Watch…" }
        guard session.isPaired else { return "No Apple Watch is paired with this iPhone." }
        guard session.isWatchAppInstalled else { return "ScooterRide isn't installed on your Apple Watch." }
        return session.isReachable ? "Apple Watch connected." : "Rides sync when your Apple Watch is nearby."
    }

    /// Deletes a ride here and asks the watch to delete its copy (queued until the watch is
    /// reachable). The ride is remembered as deleted so it is never re-imported.
    func deleteRide(_ id: UUID) throws {
        if store?.contains(id: id) == true { try store?.delete(id: id) }
        state.deleted.insert(id)
        persist()
        session?.transferUserInfo(SyncMessage.rideDeleted(id: id).dictionary)
    }

    /// Asks the watch to end the active ride. Only sent when the watch is reachable right
    /// now; it is never queued, so it can't end a ride later than intended.
    func requestEndRideOnWatch() async -> String {
        guard let session else { return "This iPhone doesn't support Apple Watch." }
        for _ in 0..<30 where session.activationState != .activated {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
            return "ScooterRide isn't available on a paired Apple Watch."
        }
        guard session.isReachable else {
            return "Apple Watch isn't reachable right now. End the ride on the watch, or ask Siri on the watch."
        }
        let request = SyncMessage.endRideRequest(issuedAt: Date()).dictionary
        do {
            let reply: [String: Any] = try await withCheckedThrowingContinuation { continuation in
                session.sendMessage(request, replyHandler: { continuation.resume(returning: $0) },
                                    errorHandler: { continuation.resume(throwing: $0) })
            }
            return (reply["ok"] as? Bool) == true ? "Scooter ride ended and saved on Apple Watch."
                                                   : "No scooter ride is in progress on Apple Watch."
        } catch {
            return "Couldn't reach Apple Watch: \(error.localizedDescription)"
        }
    }

    private func inventoryReply(for ids: [UUID]) -> SyncMessage {
        Inventory.reply(to: ids, isStored: { self.store?.contains(id: $0) == true }, deleted: state.deleted)
    }

    private func importReceived(_ data: Data?, expectedID: UUID?) {
        guard let data, let store else { lastError = "A ride arrived but could not be read."; return }
        let outcome = RideImporter.importRide(data: data, into: store, deleted: state.deleted, expectedID: expectedID)
        if let id = outcome.acknowledgedID {
            session?.transferUserInfo(SyncMessage.rideAcknowledged(id: id).dictionary)
            if case .ignoredDeleted = outcome {
                session?.transferUserInfo(SyncMessage.rideDeleted(id: id).dictionary)
            }
        }
        if case .rejected(let reason) = outcome { lastError = "A ride from Apple Watch was not imported: \(reason)." }
        onChange?()
    }

    private func persist() {
        do { try stateStore?.save(state) } catch { lastError = "Could not save sync state: \(error.localizedDescription)" }
    }
}

extension PhoneSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in
            if let message { self.lastError = "Watch connectivity: \(message)" }
            self.onChange?()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()   // e.g. after switching to another Apple Watch
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.onChange?() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.onChange?() }
    }

    /// The watch's check-in: answers which of its rides are stored or deleted here. The system
    /// wakes this app in the background to deliver it, even when the iPhone is locked.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard case .inventoryRequest(let ids)? = SyncMessage(dictionary: message) else {
            replyHandler([:])
            return
        }
        Task { @MainActor in replyHandler(self.inventoryReply(for: ids).dictionary) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is only guaranteed to exist until this method returns: read it now.
        let data = try? Data(contentsOf: file.fileURL)
        let id = RideFileMetadata.rideID(from: file.metadata)
        Task { @MainActor in self.importReceived(data, expectedID: id) }
    }
}
