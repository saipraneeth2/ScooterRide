import Testing
import Foundation
@testable import RideKit

@Suite("Persistence")
struct RideStoreTests {
    private func makeStore() throws -> RideStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RideKitTests-\(UUID().uuidString)", isDirectory: true)
        return try RideStore(directory: dir)
    }

    private func finishedRide(startOffset: TimeInterval = 0, seconds: Int = 30) throws -> RideSession {
        var r = RideRecorder()
        let start = Synthetic.t0.addingTimeInterval(startOffset)
        try r.start(at: start, source: .watch)
        _ = Synthetic.feed(Synthetic.line(seconds: seconds, speed: 6, startTime: startOffset), into: &r)
        return try r.end(at: start.addingTimeInterval(Double(seconds)))
    }

    @Test func roundTripsARide() throws {
        let store = try makeStore()
        let ride = try finishedRide()
        try store.save(ride)
        #expect(try store.load(id: ride.id) == ride)
    }

    @Test func listsNewestFirstAndSkipsCorruptFiles() throws {
        let store = try makeStore()
        let older = try finishedRide(startOffset: 0)
        let newer = try finishedRide(startOffset: 3600)
        try store.save(older)
        try store.save(newer)
        let junk = store.directory.appendingPathComponent("ride-\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: junk)
        let result = store.all()
        #expect(result.rides.map(\.id) == [newer.id, older.id])
        // Compare names: macOS may report the temp folder as /var or /private/var.
        #expect(result.unreadable.map(\.lastPathComponent) == [junk.lastPathComponent])
    }

    @Test func deletesRides() throws {
        let store = try makeStore()
        let ride = try finishedRide()
        try store.save(ride)
        try store.delete(id: ride.id)
        #expect(store.all().rides.isEmpty)
        #expect(throws: RideStoreError.notFound(ride.id)) { try store.delete(id: ride.id) }
    }

    @Test func overwritesAtomically() throws {
        let store = try makeStore()
        var ride = try finishedRide()
        try store.save(ride)
        ride.distanceMeters = 1234
        try store.save(ride)
        #expect(try store.load(id: ride.id).distanceMeters == 1234)
        #expect(store.all().rides.count == 1)
    }

    @Test func recoversAnInterruptedRideFromItsCheckpoint() throws {
        let store = try makeStore()
        var r = RideRecorder()
        try r.start(at: Synthetic.t0, source: .watch)
        _ = Synthetic.feed(Synthetic.line(seconds: 40, speed: 6), into: &r)
        try store.saveCheckpoint(try #require(r.session))
        // ...the app is terminated here; on next launch:
        let recovered = try #require(try store.recoverCheckpoint())
        #expect(recovered.recovered)
        #expect(recovered.endDate == Synthetic.t0.addingTimeInterval(40))
        #expect(recovered.intervals.allSatisfy { $0.end != nil })
        #expect(abs(recovered.activeDuration(at: .distantFuture) - 40) < 0.001)
        #expect(store.loadCheckpoint() == nil)
        #expect(try store.load(id: recovered.id) == recovered)
    }

    @Test func noCheckpointMeansNothingToRecover() throws {
        let store = try makeStore()
        #expect(try store.recoverCheckpoint() == nil)
    }

    @Test func rejectionCountsEncodeAsReadableKeys() throws {
        var ride = try finishedRide()
        ride.rejectedSampleCounts[.poorAccuracy] = 3
        let store = try makeStore()
        try store.save(ride)
        let file = store.directory.appendingPathComponent("ride-\(ride.id.uuidString).json")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\"poorAccuracy\":3"))
    }
}
