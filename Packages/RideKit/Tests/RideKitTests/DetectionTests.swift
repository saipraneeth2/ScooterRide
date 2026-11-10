import Testing
import Foundation
@testable import RideKit

// All inputs here are SYNTHETIC. Nothing was recorded from a real device or scooter.

private func t(_ s: TimeInterval) -> Date { Synthetic.t0.addingTimeInterval(s) }

/// A finished ride along a straight line at constant speed.
private func ride(seconds: Int, speed: Double, motion: [(MotionKind, TimeInterval)] = []) throws -> RideSession {
    var r = RideRecorder()
    try r.start(at: Synthetic.t0, source: .watch)
    var at: TimeInterval = 0
    for (kind, duration) in motion {
        r.ingestMotion(kind, at: t(at))
        at += duration
    }
    _ = Synthetic.feed(Synthetic.line(seconds: seconds, speed: speed), into: &r)
    return try r.end(at: t(Double(seconds)))
}

@Suite("Motion")
struct MotionTests {
    @Test func vehicleKindsWinAndLowConfidenceIsUnknown() {
        #expect(MotionKind.classify(automotive: true, cycling: false, running: false, walking: false, stationary: true, confidence: 2) == .automotive)
        #expect(MotionKind.classify(automotive: false, cycling: true, running: false, walking: true, stationary: false, confidence: 1) == .cycling)
        #expect(MotionKind.classify(automotive: false, cycling: false, running: false, walking: true, stationary: false, confidence: 1) == .walking)
        #expect(MotionKind.classify(automotive: true, cycling: false, running: false, walking: false, stationary: false, confidence: 0) == .unknown)
        #expect(MotionKind.classify(automotive: false, cycling: false, running: false, walking: false, stationary: false, confidence: 2) == .unknown)
    }

    @Test func recorderCountsMotionOnlyWhileRecording() throws {
        var r = RideRecorder()
        try r.start(at: t(0), source: .watch)
        r.ingestMotion(.cycling, at: t(0))
        r.ingestMotion(.stationary, at: t(60))     // 60 s cycling
        try r.pause(at: t(90))                    // 30 s stationary
        r.ingestMotion(.walking, at: t(100))      // while paused: not counted
        try r.resume(at: t(200))
        let ride = try r.end(at: t(220))          // 20 s walking, from the resume
        let m = try #require(ride.motion)
        #expect(m.seconds[.cycling] == 60)
        #expect(m.seconds[.stationary] == 30)
        #expect(m.seconds[.walking] == 20)
        #expect(m.total == 110)
        #expect(m.share { $0.isRidingLike } == 60.0 / 110.0)
    }

    @Test func ridesWithoutMotionStillLoadAndRoundTrip() throws {
        let withMotion = try ride(seconds: 20, speed: 6, motion: [(.cycling, 20)])
        let data = try RideStore.makeEncoder().encode(withMotion)
        #expect(try RideStore.decodeRide(data) == withMotion)

        // A file written before motion existed: drop the key and it must still load.
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "motion")
        let old = try RideStore.decodeRide(try JSONSerialization.data(withJSONObject: json))
        #expect(old.motion == nil)
        #expect(old.id == withMotion.id)
    }
}

@Suite("Stop suggestion")
struct StopDetectorTests {
    /// Feeds readings every `step` seconds and returns the times a suggestion fired.
    private func run(_ d: inout StopDetector, from: TimeInterval, to: TimeInterval, step: TimeInterval,
                     speed: Double?, motion: MotionKind?) -> [TimeInterval] {
        var fired: [TimeInterval] = []
        for s in stride(from: from, through: to, by: step) {
            if d.update(speed: speed, motion: motion, at: t(s)) { fired.append(s) }
        }
        return fired
    }

    @Test func suggestsOnceAfterThreeMinutesStopped() {
        var d = StopDetector()
        let fired = run(&d, from: 0, to: 400, step: 10, speed: 0.2, motion: .stationary)
        #expect(fired == [180])
    }

    @Test func movingOrRidingMotionResetsTheClock() {
        var d = StopDetector()
        let before = run(&d, from: 0, to: 170, step: 10, speed: 0.3, motion: nil)
        let moving = d.update(speed: 6, motion: nil, at: t(175))
        let after = run(&d, from: 180, to: 360, step: 10, speed: 0.3, motion: nil)
        #expect(before.isEmpty)
        #expect(!moving)
        #expect(after == [360])   // 180 s after the restart

        var e = StopDetector()
        let slowButRiding = run(&e, from: 0, to: 400, step: 10, speed: 0.3, motion: .cycling)
        #expect(slowButRiding.isEmpty)
    }

    @Test func gapsAndMissingEvidenceDoNotCount() {
        var d = StopDetector()
        let a = d.update(speed: 0.2, motion: nil, at: t(0))
        let b = d.update(speed: 0.2, motion: nil, at: t(100))   // 100 s gap: restart at 100
        let c = d.update(speed: 0.2, motion: nil, at: t(270))   // 170 s gap: restart again
        #expect(!a && !b && !c)
        #expect(d.stoppedSince == t(270))

        var e = StopDetector()
        let noEvidence = run(&e, from: 0, to: 400, step: 10, speed: nil, motion: nil)
        #expect(noEvidence.isEmpty)
    }

    @Test func motionAloneCanCarryAStopWhenGPSHasNoSpeed() {
        var d = StopDetector()
        let fired = run(&d, from: 0, to: 200, step: 20, speed: nil, motion: .walking)
        #expect(fired == [180])
    }

    @Test func keepRidingSnoozesTenMinutes() {
        var d = StopDetector()
        let first = run(&d, from: 0, to: 180, step: 10, speed: 0, motion: nil)
        d.dismiss(at: t(180))
        let later = run(&d, from: 190, to: 1000, step: 10, speed: 0, motion: nil)
        #expect(first == [180])
        #expect(later == [780])   // snooze ends at 780; still stopped since 190
    }
}

@Suite("Start suggestion")
struct StartDetectorTests {
    private func feed(_ d: inout StartDetector, _ samples: [LocationSample]) -> [StartReason] {
        samples.compactMap { d.update($0, at: $0.timestamp.addingTimeInterval(0.2)) }
    }

    @Test func sustainedScooterSpeedSuggestsOnce() {
        var d = StartDetector()
        let reasons = feed(&d, Synthetic.line(seconds: 30, speed: 5.5))
        #expect(reasons == [.movingAtScooterSpeed(medianSpeed: 5.5)])
    }

    @Test func walkingCarSpeedAndInaccurateFixesDoNotSuggest() {
        var walk = StartDetector(), car = StartDetector(), blurry = StartDetector()
        let w = feed(&walk, Synthetic.line(seconds: 30, speed: 1.4))
        let c = feed(&car, Synthetic.line(seconds: 30, speed: 15))
        let b = feed(&blurry, Synthetic.line(seconds: 30, speed: 5.5, accuracy: 40))
        #expect(w.isEmpty)
        #expect(c.isEmpty)
        #expect(b.isEmpty)
    }

    @Test func nearbyScooterNeedsAUsableSignalAndRespectsSnooze() {
        var d = StartDetector()
        let weak = d.scooterSeen(rssi: -95, at: t(0))
        let strong = d.scooterSeen(rssi: -60, at: t(1))
        let repeated = d.scooterSeen(rssi: -60, at: t(2))       // already suggested
        d.dismiss(at: t(3))
        let snoozed = d.scooterSeen(rssi: -60, at: t(200))      // snoozed for 5 min
        let afterSnooze = d.scooterSeen(rssi: -60, at: t(304))
        #expect(weak == nil)
        #expect(strong == .scooterNearby)
        #expect(repeated == nil)
        #expect(snoozed == nil)
        #expect(afterSnooze == .scooterNearby)
    }
}

@Suite("Ride-type estimate")
struct RideTypeTests {
    @Test func labelsScooterWalkingAndCarSpeeds() throws {
        #expect(RideTypeEstimator.estimate(try ride(seconds: 120, speed: 6)).type == .scooterLike)
        #expect(RideTypeEstimator.estimate(try ride(seconds: 120, speed: 1.6)).type == .mostlyWalking)
        #expect(RideTypeEstimator.estimate(try ride(seconds: 120, speed: 15)).type == .fasterThanScooter)
        #expect(RideTypeEstimator.estimate(try ride(seconds: 120, speed: 0.2)).type == .notEnoughData)
        #expect(RideTypeEstimator.estimate(try ride(seconds: 15, speed: 6)).type == .notEnoughData)
    }

    @Test func motionOnFootOverridesScooterLikeSpeed() throws {
        let est = RideTypeEstimator.estimate(try ride(seconds: 120, speed: 3, motion: [(.walking, 100), (.cycling, 20)]))
        #expect(est.type == .mostlyWalking)
        #expect(est.onFootMotionShare == 100.0 / 120.0)
    }

    @Test func reportsTheNumbersBehindTheLabel() throws {
        let est = RideTypeEstimator.estimate(try ride(seconds: 120, speed: 6, motion: [(.cycling, 120)]))
        #expect(est.medianMovingSpeed == 6)
        #expect(est.movingSeconds >= 110)
        #expect(est.fastShare == 0)
        #expect(est.ridingMotionShare == 1)
    }
}

@Suite("iPhone riding alert")
struct RidingAlertTests {
    let policy = RidingAlertPolicy()
    let now = t(1000)

    @Test func alertsAfterAMinuteOfCycling() {
        let acts = [MotionActivitySpan(start: t(700), kind: .walking), MotionActivitySpan(start: t(900), kind: .cycling)]
        #expect(policy.decide(activities: acts, now: now, lastAlert: nil, watchIsRecording: false, impliedSpeed: nil) == .alert)
    }

    @Test func skipsForEveryGuard() {
        let cycling = [MotionActivitySpan(start: t(800), kind: .cycling)]
        #expect(policy.decide(activities: cycling, now: now, lastAlert: nil, watchIsRecording: true, impliedSpeed: nil) != .alert)
        #expect(policy.decide(activities: cycling, now: now, lastAlert: t(0), watchIsRecording: false, impliedSpeed: nil) != .alert)
        #expect(policy.decide(activities: cycling, now: now, lastAlert: nil, watchIsRecording: false, impliedSpeed: 20) != .alert)
        let car = [MotionActivitySpan(start: t(800), kind: .automotive)]
        #expect(policy.decide(activities: car, now: now, lastAlert: nil, watchIsRecording: false, impliedSpeed: nil) != .alert)
        #expect(policy.decide(activities: car, now: now, lastAlert: nil, watchIsRecording: false, impliedSpeed: 6) == .alert)
        let brief = [MotionActivitySpan(start: t(970), kind: .cycling)]
        #expect(policy.decide(activities: brief, now: now, lastAlert: nil, watchIsRecording: false, impliedSpeed: nil) != .alert)
        let walking = [MotionActivitySpan(start: t(500), kind: .walking)]
        #expect(policy.decide(activities: walking, now: now, lastAlert: nil, watchIsRecording: false, impliedSpeed: nil) != .alert)
    }
}

@Suite("Bluetooth information")
struct BluetoothInfoTests {
    @Test func namesStandardServicesAndShortensSIGBaseUUIDs() {
        #expect(BluetoothNames.normalize("0000180a-0000-1000-8000-00805f9b34fb") == "180A")
        #expect(BluetoothNames.serviceName("180a") == "Device Information")
        #expect(BluetoothNames.serviceName(BluetoothNames.nordicUARTService.lowercased())?.hasPrefix("Nordic UART") == true)
        #expect(BluetoothNames.describeService("ABCD") == "Unrecognized service ABCD")
        #expect(BluetoothNames.describeCompany(0x004C) == "Apple (0x004C)")
        #expect(BluetoothNames.describeCompany(0x1234) == "Company 0x1234 (not in ScooterRide's list)")
        #expect(ManufacturerData.companyID(Data([0x4C, 0x00, 0x02])) == 0x004C)
        #expect(ManufacturerData.companyID(Data([0x4C])) == nil)
    }

    @Test func readsOnlyStandardValuesNeverSerialOrSystemID() {
        #expect(StandardReads.isAllowed(characteristic: "2A50"))
        #expect(StandardReads.isAllowed(characteristic: "00002a19-0000-1000-8000-00805f9b34fb"))
        #expect(!StandardReads.isAllowed(characteristic: "2A25"))   // Serial Number
        #expect(!StandardReads.isAllowed(characteristic: "2A23"))   // System ID
        #expect(!StandardReads.isAllowed(characteristic: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"))
    }

    @Test func decodesStandardValues() {
        #expect(StandardReads.describe(characteristic: "2A19", value: Data([87])) == "87%")
        #expect(StandardReads.describe(characteristic: "2A19", value: Data([150])) == "Invalid battery value")
        #expect(StandardReads.describe(characteristic: "2A26", value: Data("1.2.3\0".utf8)) == "1.2.3")
        #expect(StandardReads.describe(characteristic: "2A29", value: Data([0xFF, 0xFE])) == "FF FE")
        let pnp = PnPID(Data([0x01, 0x59, 0x00, 0x34, 0x12, 0x00, 0x01]))
        #expect(pnp == PnPID(Data([0x01, 0x59, 0x00, 0x34, 0x12, 0x00, 0x01, 0xAA])))
        #expect(pnp?.vendorID == 0x0059)
        #expect(pnp?.productID == 0x1234)
        #expect(pnp?.productVersion == 0x0100)
        #expect(pnp?.description == "Vendor 0x0059 (Nordic Semiconductor, Bluetooth SIG id), product 0x1234, version 0x0100")
        #expect(PnPID(Data([1, 2, 3])) == nil)
    }

    @Test func masksSerialLikeNames() {
        // Made-up serial-like name; not a real device's.
        #expect(DeviceNameMask.display("ZX12AB34CD56") == "ZX…CD56")
        #expect(DeviceNameMask.display("Scooter ZX12AB34CD56") == "Scooter ZX…CD56")
        #expect(DeviceNameMask.display("AirPods Pro") == "AirPods Pro")
        #expect(DeviceNameMask.display("ABCDEFGHIJKL") == "ABCDEFGHIJKL")   // no digits: not a serial
        #expect(DeviceNameMask.display(nil) == "Unnamed device")
        #expect(DeviceNameMask.display("  ") == "Unnamed device")
    }

    @Test func scannerSourceNeverWritesOrSubscribes() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/RideKit/BluetoothScanner.swift")
        let code = try String(contentsOf: source, encoding: .utf8)
        for forbidden in ["writeValue(", "setNotifyValue(", "openL2CAPChannel(", ".writeWithoutResponse"] {
            #expect(!code.contains(forbidden), "BluetoothScanner must never call \(forbidden)")
        }
    }
}
