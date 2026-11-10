import Foundation

// Watch <-> iPhone sync, as pure logic. The apps move these values with WatchConnectivity:
//
//   watch  --transferFile(ride JSON, metadata)-->  iPhone   (queued by the system; works offline)
//   iPhone --transferUserInfo(.rideAcknowledged)--> watch   (watch stops re-sending that ride)
//   iPhone --transferUserInfo(.rideDeleted)------->  watch   (watch deletes its copy too)
//   iPhone --sendMessage(.endRideRequest)--------->  watch   (only when reachable; never queued)

/// Small control messages. Encoded as JSON inside a property-list dictionary.
public enum SyncMessage: Codable, Equatable, Sendable {
    case rideAcknowledged(id: UUID)
    case rideDeleted(id: UUID)
    case endRideRequest(issuedAt: Date)

    public static let payloadKey = "scooterride.sync.v1"

    /// An end request older than this is ignored, so a delayed message can never end
    /// a ride long after the rider asked.
    public static let endRequestMaxAge: TimeInterval = 60

    public var dictionary: [String: Any] {
        [Self.payloadKey: (try? JSONEncoder().encode(self)) ?? Data()]
    }

    public init?(dictionary: [String: Any]) {
        guard let data = dictionary[Self.payloadKey] as? Data,
              let message = try? JSONDecoder().decode(SyncMessage.self, from: data) else { return nil }
        self = message
    }

    public func isFresh(now: Date) -> Bool {
        guard case .endRideRequest(let issuedAt) = self else { return true }
        let age = now.timeIntervalSince(issuedAt)
        return age >= -5 && age <= Self.endRequestMaxAge
    }
}

/// Metadata attached to a transferred ride file.
public enum RideFileMetadata {
    public static func make(id: UUID) -> [String: Any] {
        ["kind": "ride", "rideID": id.uuidString, "schema": RideSession.currentSchemaVersion]
    }

    public static func rideID(from metadata: [String: Any]?) -> UUID? {
        guard metadata?["kind"] as? String == "ride", let s = metadata?["rideID"] as? String else { return nil }
        return UUID(uuidString: s)
    }
}

/// What one device knows about sync. Persisted next to the rides.
public struct SyncState: Codable, Equatable, Sendable {
    /// Watch: rides the iPhone has confirmed it stored.
    public var acknowledged: Set<UUID> = []
    /// Both: rides deleted by the user. Never re-sent, never re-imported.
    public var deleted: Set<UUID> = []

    public init() {}
}

public enum SyncPlanner {
    /// Rides the watch should (re)send: stored, not yet acknowledged, not deleted,
    /// and not already queued in an outstanding transfer.
    public static func ridesToSend(stored: [UUID], state: SyncState, inFlight: Set<UUID>) -> [UUID] {
        stored.filter { !state.acknowledged.contains($0) && !state.deleted.contains($0) && !inFlight.contains($0) }
    }
}

/// Reads and writes SyncState as JSON (sync-state.json in the rides folder).
public struct SyncStateStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("sync-state.json")
    }

    public func load() -> SyncState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(SyncState.self, from: data) else { return SyncState() }
        return state
    }

    public func save(_ state: SyncState) throws {
        try JSONEncoder().encode(state).write(to: fileURL, options: [.atomic])
    }
}

public enum ImportOutcome: Equatable, Sendable {
    case saved(UUID)
    case alreadyHad(UUID)
    case ignoredDeleted(UUID)
    case rejected(String)

    /// The ride id to acknowledge to the sender, if any.
    public var acknowledgedID: UUID? {
        switch self {
        case .saved(let id), .alreadyHad(let id), .ignoredDeleted(let id): return id
        case .rejected: return nil
        }
    }
}

/// Validates and stores a ride received from the other device. Idempotent: receiving the
/// same ride twice is harmless, and a ride the user deleted is never brought back.
public enum RideImporter {
    public static func importRide(data: Data, into store: RideStore, deleted: Set<UUID>,
                                  expectedID: UUID? = nil) -> ImportOutcome {
        let ride: RideSession
        do {
            ride = try RideStore.decodeRide(data)
        } catch {
            return .rejected("unreadable ride file")
        }
        if let expectedID, expectedID != ride.id { return .rejected("ride id does not match its metadata") }
        guard ride.schemaVersion <= RideSession.currentSchemaVersion else {
            return .rejected("ride was saved by a newer app version (schema \(ride.schemaVersion))")
        }
        guard ride.isFinished else { return .rejected("ride is still in progress") }
        if deleted.contains(ride.id) { return .ignoredDeleted(ride.id) }
        if let existing = try? store.load(id: ride.id), existing == ride { return .alreadyHad(ride.id) }
        do {
            try store.save(ride)
            return .saved(ride.id)
        } catch {
            return .rejected("could not save: \(error.localizedDescription)")
        }
    }
}
