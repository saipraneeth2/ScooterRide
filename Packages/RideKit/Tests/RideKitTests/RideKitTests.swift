import Testing
import Foundation
@testable import RideKit

private func approx(_ a: Double?, _ b: Double, tol: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tol
}

@Suite("Units and formatting")
struct UnitsTests {
    @Test func conversions() {
        #expect(approx(Units.mph(fromMetersPerSecond: 10), 22.369, tol: 0.001))
        #expect(approx(Units.miles(fromMeters: 1609.344), 1, tol: 1e-9))
        #expect(approx(Units.metersPerSecond(fromMph: 20), 8.9408, tol: 1e-4))
    }

    @Test func formatting() {
        #expect(RideFormat.speed(nil) == "--")
        #expect(RideFormat.speed(-1) == "--")
        #expect(RideFormat.speed(8.9408) == "20.0")
        #expect(RideFormat.distance(1609.344) == "1.00 mi")
        #expect(RideFormat.duration(65) == "1:05")
        #expect(RideFormat.duration(3723) == "1:02:03")
    }

    @Test func greatCircleDistance() {
        #expect(approx(GeoMath.distance(lat1: 0, lon1: 0, lat2: 1, lon2: 0), Synthetic.metersPerDegreeLat, tol: 0.01))
        let a = Synthetic.sample(at: 0), b = Synthetic.sample(northMeters: 100, at: 1)
        #expect(approx(GeoMath.distance(a, b), 100, tol: 0.01))
    }
}

@Suite("GPS filtering")
struct FilterTests {
    let filter = LocationFilter()
    let now = Synthetic.t0.addingTimeInterval(1.2)

    @Test func acceptsAGoodFix() {
        #expect(filter.evaluate(Synthetic.sample(at: 1), previous: nil, now: now) == .accept)
    }

    @Test func rejectsInvalidCoordinates() {
        #expect(filter.evaluate(Synthetic.sample(at: 1, accuracy: -1), previous: nil, now: now) == .reject(.invalidCoordinate))
        let nullIsland = LocationSample(timestamp: Synthetic.t0, latitude: 0, longitude: 0, horizontalAccuracy: 5)
        #expect(filter.evaluate(nullIsland, previous: nil, now: now) == .reject(.invalidCoordinate))
    }

    @Test func rejectsPoorAccuracyAndStaleFixes() {
        #expect(filter.evaluate(Synthetic.sample(at: 1, accuracy: 50), previous: nil, now: now) == .reject(.poorAccuracy))
        let stale = Synthetic.sample(at: 1)
        #expect(filter.evaluate(stale, previous: nil, now: stale.timestamp.addingTimeInterval(30)) == .reject(.stale))
    }

    @Test func rejectsOutOfOrderAndDuplicateFixes() {
        let prev = Synthetic.sample(at: 5)
        #expect(filter.evaluate(Synthetic.sample(at: 4), previous: prev, now: prev.timestamp) == .reject(.outOfOrder))
        #expect(filter.evaluate(Synthetic.sample(at: 5), previous: prev, now: prev.timestamp) == .reject(.duplicate))
    }

    @Test func rejectsImplausibleSpeedAndJumps() {
        let fast = Synthetic.sample(at: 1, speed: 25)  // ~56 mph reported
        #expect(filter.evaluate(fast, previous: nil, now: now) == .reject(.implausibleSpeed))
        let prev = Synthetic.sample(at: 0)
        let jump = Synthetic.sample(northMeters: 1000, at: 1)
        #expect(filter.evaluate(jump, previous: prev, now: now) == .reject(.implausibleJump))
    }

    @Test func toleratesMovesInsideTheErrorCircle() {
        let prev = Synthetic.sample(at: 0, accuracy: 20)
        let wobble = Synthetic.sample(northMeters: 30, at: 1, accuracy: 20)   // 30 m < 40 m combined slack
        #expect(filter.evaluate(wobble, previous: prev, now: now) == .accept)
    }
}

@Suite("Speed estimation")
struct SpeedTests {
    @Test func prefersAccurateReportedSpeed() {
        let e = SpeedEstimator()
        #expect(e.rawSpeed(for: Synthetic.sample(at: 1, speed: 6.5, speedAccuracy: 0.4), previous: nil) == 6.5)
    }

    @Test func derivesSpeedWhenReportedSpeedIsUnreliable() {
        let e = SpeedEstimator()
        let prev = Synthetic.sample(at: 0)
        let cur = Synthetic.sample(northMeters: 7, at: 1, speed: 3, speedAccuracy: 9)   // poor accuracy
        #expect(approx(e.rawSpeed(for: cur, previous: prev), 7, tol: 0.01))
        #expect(e.rawSpeed(for: Synthetic.sample(at: 1), previous: nil) == nil)
    }

    @Test func medianSuppressesASpike() {
        var e = SpeedEstimator()
        _ = e.push(7); _ = e.push(7)
        #expect(e.push(16) == 7)
    }

    @Test func treatsCrawlingAsStopped() {
        var e = SpeedEstimator()
        #expect(e.push(0.3) == 0)
    }

    @Test func ignoresDerivedSpeedFromFixesTooCloseOrTooFast() {
        let e = SpeedEstimator()
        let prev = Synthetic.sample(at: 0, accuracy: 19.8)
        // 4.9 m in 0.092 s: GPS warm-up jitter, not 120 mph.
        #expect(e.rawSpeed(for: Synthetic.sample(northMeters: 4.9, at: 0.092), previous: prev) == nil)
        // 60 m in 1 s (134 mph): beyond any scooter.
        #expect(e.rawSpeed(for: Synthetic.sample(northMeters: 60, at: 1), previous: prev) == nil)
        #expect(approx(e.rawSpeed(for: Synthetic.sample(northMeters: 8, at: 1), previous: prev), 8, tol: 0.01))
    }

    @Test func settlesOnlyWithAFullWindow() {
        var e = SpeedEstimator()
        _ = e.push(53.7)
        let afterOne = e.isSettled
        _ = e.push(0)
        let afterTwo = e.isSettled
        _ = e.push(0)
        #expect(!afterOne && !afterTwo)
        #expect(e.isSettled)
    }

    /// Shape of a real watch recording (values are synthetic): two warm-up fixes 0.09 s apart
    /// with 4.9 m of jitter, then a stationary rider with Doppler speed 0. Before the fix this
    /// produced a 120 mph point and a 60 mph max speed.
    @Test func warmUpJitterNeverBecomesASpeed() throws {
        var r = RideRecorder()
        try r.start(at: Synthetic.t0, source: .watch)
        var fixes = [Synthetic.sample(at: 0.07, accuracy: 19.8),
                     Synthetic.sample(northMeters: 4.9, at: 0.16, accuracy: 5),
                     Synthetic.sample(northMeters: 5, at: 5.41, accuracy: 12.3, speed: 0, speedAccuracy: 1.45)]
        fixes += (6...24).map { Synthetic.sample(northMeters: 5, at: Double($0) + 0.41, accuracy: 10, speed: 0, speedAccuracy: 1.4) }
        let decisions = Synthetic.feed(fixes, into: &r)
        let ride = try r.end(at: Synthetic.t0.addingTimeInterval(25))
        #expect(decisions.allSatisfy { $0.isAccepted })   // the fixes are fine; only the speed math was wrong
        #expect((ride.maxSpeedMetersPerSecond ?? 0) < 0.5)
        #expect(ride.route.allSatisfy { ($0.estimatedSpeed ?? 0) < 0.5 })
        #expect(RideTypeEstimator.estimate(ride).type == .notEnoughData)
    }
}

@Suite("Ride recorder: metrics")
struct RecorderMetricTests {
    @Test func straightRideProducesExpectedDistanceAndSpeeds() throws {
        var r = RideRecorder()
        try r.start(at: Synthetic.t0, source: .watch)
        let decisions = Synthetic.feed(Synthetic.line(seconds: 60, speed: 7), into: &r)
        #expect(decisions.allSatisfy { $0.isAccepted })
        let m = r.metrics(at: Synthetic.t0.addingTimeInterval(60.5))
        #expect(approx(m.distanceMeters, 420, tol: 420 * 0.01))
        #expect(approx(m.currentSpeed, 7, tol: 0.01))
        #expect(approx(m.maxSpeed, 7, tol: 0.01))
        let ended = try r.end(at: Synthetic.t0.addingTimeInterval(60))
        #expect(approx(ended.averageSpeed(at: Synthetic.t0), 7, tol: 0.1))
        #expect(ended.route.count == 61)
    }

    @Test func maxSpeedIgnoresASingleSpike() throws {
        var r = RideRecorder()
        try r.start(at: Synthetic.t0, source: .watch)
        var track = Synthetic.line(seconds: 20, speed: 7)
        track[10].speed = 16   // one bad Doppler reading, still under the plausibility cap
        _ = Synthetic.feed(track, into: &r)
        #expect(approx(r.metrics(at: Synthetic.t0.addingTimeInterval(20.5)).maxSpeed, 7, tol: 0.01))
    }

    @Test func firstFixAloneDoesNotSetMaxSpeed() throws {
        var r = RideRecorder()
        try r.start(at: Synthetic.t0, source: .watch)
        _ = Synthetic.feed([Synthetic.sample(at: 0, speed: 9)], into: &r)
        #expect(r.metrics(at: Synthetic.t0.addingTimeInterval(0.5)).maxSpeed == nil)
    }

    @Test func stationaryJitterAddsNoDistance() throws {
        var r = RideRecorder()
        try r.start(at: Synthetic.t0, source: .watch)
        let jitter = (0..<120).map { i in
            Synthetic.sample(northMeters: 3 * sin(Double(i)), eastMeters: 3 * cos(Double(i) * 1.7),
                             at: Double(i), accuracy: 8, speed: 0)
        }
        _ = Synthetic.feed(jitter, into: &r)
        let m = r.metrics(at: Synthetic.t0.addingTimeInterval(120))
        #expect(m.distanceMeters < 5)
        #expect(m.currentSpeed == 0)
    }

    @Test func slowSteadyMovementStillCounts() throws {
        // 0.8 m/s for 60 s without Doppler speed: each step is below the jitter threshold,
        // but the anchor logic must still accumulate the ~48 m.
        var r = RideRecorder()
        try r.start(at: Synthetic.t0, source: .watch)
        _ = Synthetic.feed(Synthetic.line(seconds: 60, speed: 0.8, reportSpeed: false), into: &r)
        #expect(approx(r.metrics(at: Synthetic.t0.addingTimeInterval(60.5)).distanceMeters, 48, tol: 8))
    }

    @Test func pauseExcludesTimeAndDistance() throws {
        var r = RideRecorder()
        try r.start(at: Synthetic.t0, source: .watch)
        _ = Synthetic.feed(Synthetic.line(seconds: 30, speed: 7), into: &r)                      // 210 m
        try r.pause(at: Synthetic.t0.addingTimeInterval(30))
        let whilePaused = Synthetic.feed(Synthetic.line(seconds: 10, speed: 7, startTime: 40, startNorth: 300), into: &r)
        #expect(whilePaused.allSatisfy { $0 == .reject(.notRecording) })
        try r.resume(at: Synthetic.t0.addingTimeInterval(90))
        _ = Synthetic.feed(Synthetic.line(seconds: 30, speed: 7, startTime: 90, startNorth: 710), into: &r) // 210 m, 500 m gap ignored
        let ride = try r.end(at: Synthetic.t0.addingTimeInterval(120))
        #expect(approx(ride.distanceMeters, 420, tol: 5))
        #expect(approx(ride.activeDuration(at: Synthetic.t0), 60, tol: 0.001))
        #expect(Set(ride.route.map(\.segment)) == [0, 1])
        #expect(ride.intervals.count == 2)
    }

    @Test func gpsStatusAndStaleSpeed() throws {
        var r = RideRecorder()
        try r.start(at: Synthetic.t0, source: .watch)
        #expect(r.metrics(at: Synthetic.t0).gps == .searching)
        _ = Synthetic.feed(Synthetic.line(seconds: 3, speed: 6), into: &r)
        #expect(r.metrics(at: Synthetic.t0.addingTimeInterval(3.5)).gps == .good)
        let later = r.metrics(at: Synthetic.t0.addingTimeInterval(9))
        #expect(later.currentSpeed == nil)          // > 5 s without a fix
        #expect(r.metrics(at: Synthetic.t0.addingTimeInterval(20)).gps == .lost)
    }

    @Test func rejectionsAreCountedByReason() throws {
        var r = RideRecorder()
        try r.start(at: Synthetic.t0, source: .watch)
        _ = r.ingest(Synthetic.sample(at: 0, accuracy: 80), now: Synthetic.t0)
        _ = r.ingest(Synthetic.sample(at: 0, accuracy: -1), now: Synthetic.t0)
        #expect(r.session?.rejectedSampleCounts[.poorAccuracy] == 1)
        #expect(r.session?.rejectedSampleCounts[.invalidCoordinate] == 1)
        #expect(r.metrics(at: Synthetic.t0).rejectedSamples == 2)
    }
}

@Suite("Ride recorder: session state")
struct RecorderStateTests {
    @Test func validLifecycle() throws {
        var r = RideRecorder()
        #expect(r.state == .idle)
        try r.start(at: Synthetic.t0, source: .watch)
        #expect(r.state == .active)
        try r.pause(at: Synthetic.t0.addingTimeInterval(10))
        #expect(r.state == .paused)
        try r.resume(at: Synthetic.t0.addingTimeInterval(20))
        #expect(r.state == .active)
        let ride = try r.end(at: Synthetic.t0.addingTimeInterval(25))
        #expect(r.state == .ended)
        #expect(ride.isFinished)
        #expect(approx(ride.activeDuration(at: .distantFuture), 15, tol: 0.001))
        r.reset()
        #expect(r.state == .idle && r.session == nil)
    }

    @Test func endingWhilePausedIsAllowed() throws {
        var r = RideRecorder()
        try r.start(at: Synthetic.t0, source: .watch)
        try r.pause(at: Synthetic.t0.addingTimeInterval(5))
        let ride = try r.end(at: Synthetic.t0.addingTimeInterval(100))
        #expect(approx(ride.activeDuration(at: .distantFuture), 5, tol: 0.001))
    }

    @Test func invalidTransitionsThrow() throws {
        var r = RideRecorder()
        #expect(throws: RideRecorderError.invalidTransition(from: .idle, action: "pause")) { try r.pause(at: Synthetic.t0) }
        #expect(throws: RideRecorderError.invalidTransition(from: .idle, action: "end")) { try r.end(at: Synthetic.t0) }
        try r.start(at: Synthetic.t0, source: .watch)
        #expect(throws: RideRecorderError.invalidTransition(from: .active, action: "start")) { try r.start(at: Synthetic.t0, source: .watch) }
        #expect(throws: RideRecorderError.invalidTransition(from: .active, action: "resume")) { try r.resume(at: Synthetic.t0) }
    }

    @Test func idleRecorderIgnoresGPS() {
        var r = RideRecorder()
        #expect(r.ingest(Synthetic.sample(at: 0), now: Synthetic.t0) == .reject(.notRecording))
        #expect(r.metrics(at: Synthetic.t0).gps == .off)
    }
}
