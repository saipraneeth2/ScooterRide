import Testing
import Foundation
@testable import RideKit

private func tempStore() throws -> RideStore {
    try RideStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("RideKitSync-\(UUID().uuidString)", isDirectory: true))
}

private func finishedRide(seconds: Int = 20) throws -> RideSession {
    var r = RideRecorder()
    try r.start(at: Synthetic.t0, source: .watch)
    _ = Synthetic.feed(Synthetic.line(seconds: seconds, speed: 6), into: &r)
    return try r.end(at: Synthetic.t0.addingTimeInterval(Double(seconds)))
}

private func rideData(_ ride: RideSession) throws -> Data { try RideStore.makeEncoder().encode(ride) }

@Suite("Pre-start fixes")
struct PreStartTests {
    @Test func fixesBeforeStartOrResumeAreRejected() throws {
        var r = RideRecorder()
        try r.start(at: Synthetic.t0.addingTimeInterval(1), source: .watch)
        #expect(r.ingest(Synthetic.sample(at: 0.6), now: Synthetic.t0.addingTimeInterval(1.1)) == .reject(.beforeSegmentStart))
        #expect(r.ingest(Synthetic.sample(at: 1.0), now: Synthetic.t0.addingTimeInterval(1.1)) == .accept)
        try r.pause(at: Synthetic.t0.addingTimeInterval(5))
        try r.resume(at: Synthetic.t0.addingTimeInterval(20))
        #expect(r.ingest(Synthetic.sample(at: 19), now: Synthetic.t0.addingTimeInterval(20.1)) == .reject(.beforeSegmentStart))
        #expect(r.session?.rejectedSampleCounts[.beforeSegmentStart] == 2)
    }
}

@Suite("Sync messages and planning")
struct SyncMessageTests {
    @Test func messagesRoundTripThroughPropertyListDictionaries() {
        let id = UUID()
        for m in [SyncMessage.rideAcknowledged(id: id), .rideDeleted(id: id), .endRideRequest(issuedAt: Synthetic.t0)] {
            #expect(SyncMessage(dictionary: m.dictionary) == m)
            #expect(PropertyListSerialization.propertyList(m.dictionary, isValidFor: .binary))
        }
        #expect(SyncMessage(dictionary: ["something": "else"]) == nil)
    }

    @Test func staleEndRequestsAreIgnored() {
        let m = SyncMessage.endRideRequest(issuedAt: Synthetic.t0)
        #expect(m.isFresh(now: Synthetic.t0.addingTimeInterval(10)))
        #expect(!m.isFresh(now: Synthetic.t0.addingTimeInterval(SyncMessage.endRequestMaxAge + 1)))
        #expect(SyncMessage.rideDeleted(id: UUID()).isFresh(now: .distantFuture))
    }

    @Test func fileMetadataRoundTrips() {
        let id = UUID()
        #expect(RideFileMetadata.rideID(from: RideFileMetadata.make(id: id)) == id)
        #expect(RideFileMetadata.rideID(from: ["kind": "other", "rideID": id.uuidString]) == nil)
        #expect(RideFileMetadata.rideID(from: nil) == nil)
    }

    @Test func plannerSendsOnlyUnacknowledgedUndeletedIdleRides() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        var state = SyncState()
        state.acknowledged = [a]
        state.deleted = [b]
        #expect(SyncPlanner.ridesToSend(stored: [a, b, c, d], state: state, inFlight: [c]) == [d])
    }

    @Test func syncStatePersists() throws {
        let store = try tempStore()
        let stateStore = SyncStateStore(directory: store.directory)
        #expect(stateStore.load() == SyncState())
        var s = SyncState(); s.acknowledged = [UUID()]; s.deleted = [UUID()]
        try stateStore.save(s)
        #expect(stateStore.load() == s)
        #expect(store.all().rides.isEmpty)   // sync-state.json is not mistaken for a ride
    }
}

@Suite("Importing rides from the other device")
struct ImporterTests {
    @Test func savesThenRecognisesDuplicates() throws {
        let store = try tempStore()
        let ride = try finishedRide()
        let data = try rideData(ride)
        #expect(RideImporter.importRide(data: data, into: store, deleted: [], expectedID: ride.id) == .saved(ride.id))
        #expect(RideImporter.importRide(data: data, into: store, deleted: []) == .alreadyHad(ride.id))
        #expect(store.all().rides.count == 1)
    }

    @Test func neverResurrectsADeletedRide() throws {
        let store = try tempStore()
        let ride = try finishedRide()
        let outcome = RideImporter.importRide(data: try rideData(ride), into: store, deleted: [ride.id])
        #expect(outcome == .ignoredDeleted(ride.id))
        #expect(outcome.acknowledgedID == ride.id)
        #expect(store.all().rides.isEmpty)
    }

    @Test func rejectsBadInput() throws {
        let store = try tempStore()
        #expect(RideImporter.importRide(data: Data("nope".utf8), into: store, deleted: []) == .rejected("unreadable ride file"))
        var unfinished = RideRecorder()
        try unfinished.start(at: Synthetic.t0, source: .watch)
        let inProgress = try #require(unfinished.session)
        #expect(RideImporter.importRide(data: try rideData(inProgress), into: store, deleted: []) == .rejected("ride is still in progress"))
        var future = try finishedRide()
        future.schemaVersion = RideSession.currentSchemaVersion + 1
        if case .rejected = RideImporter.importRide(data: try rideData(future), into: store, deleted: []) {} else {
            Issue.record("a newer schema must be rejected")
        }
        let ride = try finishedRide()
        if case .rejected = RideImporter.importRide(data: try rideData(ride), into: store, deleted: [], expectedID: UUID()) {} else {
            Issue.record("mismatched metadata id must be rejected")
        }
        #expect(store.all().rides.isEmpty)
    }
}

@Suite("Route geometry")
struct RouteGeometryTests {
    @Test func splitsAtPauses() throws {
        var r = RideRecorder()
        try r.start(at: Synthetic.t0, source: .watch)
        _ = Synthetic.feed(Synthetic.line(seconds: 5, speed: 6), into: &r)
        try r.pause(at: Synthetic.t0.addingTimeInterval(5))
        try r.resume(at: Synthetic.t0.addingTimeInterval(10))
        _ = Synthetic.feed(Synthetic.line(seconds: 5, speed: 6, startTime: 10, startNorth: 100), into: &r)
        let ride = try r.end(at: Synthetic.t0.addingTimeInterval(15))
        let segments = RouteGeometry.segments(of: ride.route)
        #expect(segments.map(\.count) == [6, 6])
    }

    @Test func regionContainsTheRouteWithPadding() throws {
        let ride = try finishedRide(seconds: 60)   // 360 m north
        let region = try #require(RouteGeometry.region(for: ride.route))
        let lats = ride.route.map(\.sample.latitude)
        #expect(region.centerLatitude - region.latitudeDelta / 2 <= lats.min()!)
        #expect(region.centerLatitude + region.latitudeDelta / 2 >= lats.max()!)
        #expect(region.longitudeDelta >= 0.002)          // minimum span for a straight north line
        #expect(RouteGeometry.region(for: []) == nil)
    }

    @Test func simplifyKeepsEndpointsAndLimit() {
        let pts = (0..<1000).map { Coordinate(latitude: Double($0), longitude: 0) }
        let s = RouteGeometry.simplify(pts, maxPoints: 100)
        #expect(s.count == 100)
        #expect(s.first == pts.first && s.last == pts.last)
        #expect(RouteGeometry.simplify(Array(pts.prefix(10)), maxPoints: 100).count == 10)
    }
}
