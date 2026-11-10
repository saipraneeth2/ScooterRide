import Foundation
import WatchConnectivity
import RideKit

/// Sends finished rides to the iPhone and applies acknowledgements and deletions from it.
///
/// Rides go with `transferFile`, which the system queues and delivers whenever the iPhone
/// becomes reachable, including after either app has quit. Rides are re-sent until the
/// iPhone acknowledges them, so nothing is lost if a transfer fails.
@MainActor
final class WatchSync: NSObject {
    var onChange: (() -> Void)?
    /// Asked to end the active ride when the iPhone requests it. Returns whether a ride ended.
    var onEndRequest: (() -> Bool)?

    private(set) var state: SyncState
    private(set) var lastError: String?
    private let store: RideStore?
    private let stateStore: SyncStateStore?
    private let outbox: URL

    init(store: RideStore?) {
        self.store = store
        stateStore = store.map { SyncStateStore(directory: $0.directory) }
        state = stateStore?.load() ?? SyncState()
        outbox = FileManager.default.temporaryDirectory.appendingPathComponent("RideOutbox", isDirectory: true)
        super.init()
    }

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func isSynced(_ id: UUID) -> Bool { state.acknowledged.contains(id) }

    /// Queues every stored ride the iPhone has not confirmed yet.
    func syncPending() {
        guard let session, session.activationState == .activated, let store else { return }
        let stored = store.all().rides.map(\.id)
        let inFlight = Set(session.outstandingFileTransfers.compactMap { RideFileMetadata.rideID(from: $0.file.metadata) })
        for id in SyncPlanner.ridesToSend(stored: stored, state: state, inFlight: inFlight) {
            do {
                session.transferFile(try stageCopy(of: id), metadata: RideFileMetadata.make(id: id))
            } catch {
                lastError = "Could not prepare a ride for sync: \(error.localizedDescription)"
            }
        }
    }

    private var retryScheduled = false

    /// Tries again later after a failed transfer (one pending retry at a time).
    func scheduleRetry(after seconds: TimeInterval = 60) {
        guard !retryScheduled else { return }
        retryScheduled = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self.retryScheduled = false
            self.syncPending()
        }
    }

    /// Transfers a copy, so deleting or rewriting the ride never disturbs a transfer in progress.
    private func stageCopy(of id: UUID) throws -> URL {
        guard let store else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        let dest = outbox.appendingPathComponent("ride-\(id.uuidString).json")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: store.fileURL(for: id), to: dest)
        return dest
    }

    /// Applies a message from the iPhone. Returns true when it changed something.
    private func handle(_ message: SyncMessage) -> Bool {
        switch message {
        case .rideAcknowledged(let id):
            state.acknowledged.insert(id)
        case .rideDeleted(let id):
            try? store?.delete(id: id)
            state.deleted.insert(id)
            state.acknowledged.remove(id)
        case .endRideRequest:
            guard message.isFresh(now: Date()) else { return false }
            return onEndRequest?() ?? false
        }
        persist()
        onChange?()
        return true
    }

    private func persist() {
        do { try stateStore?.save(state) } catch { lastError = "Could not save sync state: \(error.localizedDescription)" }
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in
            if let message { self.lastError = "Watch connectivity: \(message)" }
            self.syncPending()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let message = SyncMessage(dictionary: userInfo) else { return }
        Task { @MainActor in _ = self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let decoded = SyncMessage(dictionary: message) else { replyHandler(["ok": false]); return }
        Task { @MainActor in replyHandler(["ok": self.handle(decoded)]) }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)   // the staged copy
        let message = error?.localizedDescription
        Task { @MainActor in
            // The ride is still unacknowledged, so the retry sends it again.
            if let message {
                self.lastError = "Ride sync will retry: \(message)"
                self.scheduleRetry()
            }
        }
    }

    // Retry when the iPhone side becomes available (seen in testing: a first attempt can
    // happen before the iPhone has registered the app).
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in if reachable { self.syncPending() } }
    }

    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor in self.syncPending() }
    }
}
