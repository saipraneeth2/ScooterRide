import Foundation

public enum RideStoreError: Error, Equatable {
    case notFound(UUID)
}

/// Local, file-based ride storage: one JSON file per ride, written atomically.
/// No accounts, servers or cloud: files live in the app's own container.
///
/// A separate checkpoint file holds the in-progress ride, so a ride survives the
/// app being terminated by the system mid-ride.
public final class RideStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601withFractionalSeconds
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601withFractionalSeconds
        return d
    }()

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Application Support/Rides inside the app container.
    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return base.appendingPathComponent("Rides", isDirectory: true)
    }

    private func fileURL(for id: UUID) -> URL { directory.appendingPathComponent("ride-\(id.uuidString).json") }
    private var checkpointURL: URL { directory.appendingPathComponent("checkpoint.json") }

    // MARK: Finished rides

    public func save(_ ride: RideSession) throws {
        let data = try encoder.encode(ride)
        lock.lock(); defer { lock.unlock() }
        try data.write(to: fileURL(for: ride.id), options: [.atomic])
    }

    public func load(id: UUID) throws -> RideSession {
        lock.lock(); defer { lock.unlock() }
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw RideStoreError.notFound(id) }
        return try decoder.decode(RideSession.self, from: Data(contentsOf: url))
    }

    /// All readable rides, newest first. Unreadable files are skipped and reported.
    public func all() -> (rides: [RideSession], unreadable: [URL]) {
        lock.lock(); defer { lock.unlock() }
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var rides: [RideSession] = []
        var bad: [URL] = []
        for url in urls where url.lastPathComponent.hasPrefix("ride-") && url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url), let r = try? decoder.decode(RideSession.self, from: data) {
                rides.append(r)
            } else {
                bad.append(url)
            }
        }
        return (rides.sorted { $0.startDate > $1.startDate }, bad)
    }

    public func delete(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw RideStoreError.notFound(id) }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: In-progress checkpoint

    public func saveCheckpoint(_ ride: RideSession) throws {
        let data = try encoder.encode(ride)
        lock.lock(); defer { lock.unlock() }
        try data.write(to: checkpointURL, options: [.atomic])
    }

    public func loadCheckpoint() -> RideSession? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: checkpointURL) else { return nil }
        return try? decoder.decode(RideSession.self, from: data)
    }

    public func clearCheckpoint() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: checkpointURL)
    }

    /// Turns a leftover checkpoint (app terminated mid-ride) into a finished ride, ending it
    /// at the last recorded fix (or its last known activity), saves it and clears the checkpoint.
    @discardableResult
    public func recoverCheckpoint() throws -> RideSession? {
        guard var ride = loadCheckpoint() else { return nil }
        let lastActivity = ride.route.last?.sample.timestamp
            ?? ride.intervals.last.map { $0.end ?? $0.start } ?? ride.startDate
        for i in ride.intervals.indices where ride.intervals[i].end == nil {
            ride.intervals[i].end = max(lastActivity, ride.intervals[i].start)
        }
        ride.endDate = ride.endDate ?? lastActivity
        ride.recovered = true
        try save(ride)
        clearCheckpoint()
        return ride
    }
}

extension JSONEncoder.DateEncodingStrategy {
    /// ISO-8601 with fractional seconds, so 1 Hz GPS timestamps round-trip exactly enough.
    static let iso8601withFractionalSeconds = JSONEncoder.DateEncodingStrategy.custom { date, encoder in
        var c = encoder.singleValueContainer()
        try c.encode(ISO8601DateFormatter.fractional.string(from: date))
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static let iso8601withFractionalSeconds = JSONDecoder.DateDecodingStrategy.custom { decoder in
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        if let d = ISO8601DateFormatter.fractional.date(from: s) ?? ISO8601DateFormatter().date(from: s) { return d }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date \(s)")
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
