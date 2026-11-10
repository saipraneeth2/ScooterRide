# ScooterRide

Track Segway Ninebot E3 Pro scooter rides on Apple Watch, separately from cycling workouts.

**Status: Phase 1** (manual ride tracking with GPS on Apple Watch). Phase 2 adds iPhone sync, ride history with maps, deletion and Siri Shortcuts. Phase 3 investigates optional, user-enabled scooter detection.

## What it does (Phase 1)

- **Controls:** Start Ride, Pause, Resume and End Ride on Apple Watch. Ending asks Save / Discard / Keep Riding.
- **Speed display:** a large GPS-estimated speed in mph, labelled *GPS EST.* with a GPS signal dot.
- **Ride metrics:** time (pauses excluded), distance, current, average and maximum GPS-estimated speed.
- **Route recording:** GPS route points are recorded and stored locally. Inaccurate, stale, out-of-order and implausible fixes are filtered out.
- **Crash protection:** the ride in progress is checkpointed every 30 s. If watchOS ends the app mid-ride, the ride is recovered on next launch.
- **Recent rides:** a list of saved rides on the watch.

## What it never does

- **No workouts:** no HealthKit is used at all. Rides are never saved as workouts, cycling or otherwise, and add no exercise minutes or calories.
- **Apple's workout detection is untouched:** ScooterRide cannot change how Apple Watch classifies motion, and there is no public API to retrain it or to silence only cycling prompts. If your watch suggests *Outdoor Cycling* while you ride, you can turn the prompt off yourself in the Watch app on iPhone: **Workout > Start Workout Reminder**. Menu names can vary by watchOS version. This turns off start reminders for every workout type.
- **No account, servers or cloud.** Rides stay in the app's own storage on the device.
- **No scooter communication.** Speed comes from GPS, not from the scooter. The E3 Pro has no documented public Bluetooth API; see *Known limitations*.

## Project layout

```
ScooterRide.xcodeproj          iOS app + watchOS app (folder-synced groups, shared schemes)
Packages/RideKit/              Swift package: units, GPS filter, speed estimator, ride state
                               machine, metrics, JSON storage. No CoreLocation/HealthKit/UI.
  Tests/RideKitTests/          Unit tests (Swift Testing), synthetic GPS tracks only
ScooterRideWatch/              watchOS app: LocationService (Core Location), RideViewModel, views
ScooterRide/                   iOS companion (Phase 1: information; Phase 2: history and sync)
Config/ScooterRideWatch-Info.plist   adds the "location" background mode for the watch app
scripts/build.sh, scripts/test.sh    command-line build and test
```

**How the pieces fit together:**
1. `LocationService` turns each `CLLocation` into a `LocationSample`.
2. `RideRecorder` (in RideKit) filters each sample, estimates speed, accumulates distance and tracks the ride state (idle → active ⇄ paused → ended).
3. `RideStore` writes each finished ride as one JSON file, plus a checkpoint file while a ride is in progress.

## Requirements

- Xcode 26.6 or later. Built here with Xcode 26.6 and the iOS/watchOS 26.5 SDKs.
- iPhone with iOS 17 or later, and a paired Apple Watch with watchOS 10 or later.
- An Apple ID added to Xcode (*Xcode > Settings > Accounts*). A free Personal Team works; its installs expire after 7 days.

## Install on your iPhone and Apple Watch (exact Xcode steps)

1. On the Mac with Xcode, open `ScooterRide.xcodeproj`.
2. In the Project navigator, select the **ScooterRide** project, then the **ScooterRide** target. Open **Signing & Capabilities**, keep **Automatically manage signing** on, and choose your **Team**.
3. Select the **ScooterRideWatch** target and choose the **same Team**.
4. If Xcode reports the bundle identifier is unavailable, change the prefix `com.saipraneethmedisetti` to something unique, in three places:
   - the **ScooterRide** target's bundle identifier
   - the **ScooterRideWatch** target's bundle identifier (keep the `.watchkitapp` suffix)
   - the ScooterRideWatch build setting **WKCompanionAppBundleIdentifier**, which must equal the iPhone app's identifier
5. Connect the iPhone with a cable, or use the same Wi-Fi network after pairing it in *Window > Devices and Simulators*. Unlock it and tap **Trust**.
6. Turn on **Developer Mode** where macOS/iOS asks for it. iPhone: *Settings > Privacy & Security > Developer Mode*, then restart. Apple Watch: *Settings > Privacy & Security > Developer Mode*, which appears after Xcode has seen the watch.
7. **Install the iPhone app:** choose the **ScooterRide** scheme and your **iPhone** as the destination, then press **Run** (⌘R).
8. **Install the watch app:** choose the **ScooterRideWatch** scheme and your **Apple Watch** as the destination, then press **Run**. The first install to a watch can take several minutes.
9. With a Personal Team, the first launch may say the developer is untrusted. Fix it on iPhone: *Settings > General > VPN & Device Management*, then trust your Apple ID.
10. On the watch, open ScooterRide, tap **Start Ride**, and allow location access **While Using the App**.

## Run in the Simulator

Choose the **ScooterRideWatch** scheme and a watch simulator. After tapping Start Ride, simulate movement in the Simulator app: *Features > Location > City Bicycle Ride* or *Freeway Drive*.

Simulated locations exercise the code path. They don't reflect real GPS quality on a moving scooter.

## Tests

```bash
scripts/test.sh
```

```bash
scripts/build.sh
```

`test.sh` runs the RideKit unit tests on macOS:
- **Speed:** unit conversions, Doppler vs. derived speed, median smoothing, a single spike ignored for max speed, stopped threshold.
- **Distance:** straight-line accuracy, stationary jitter ignored, slow movement still counted, pauses excluded.
- **Session state:** valid lifecycle, invalid transitions throw, active duration excludes pauses.
- **GPS filtering:** invalid, inaccurate, stale, out-of-order, duplicate, implausible speed and jump.
- **Persistence:** round trip, newest-first listing, corrupt files skipped, delete, atomic overwrite, checkpoint recovery.

All GPS data in the tests is **synthetic**.

`build.sh` builds the watch app and the iPhone app (with the watch app embedded) for the simulators, and compiles both for devices without signing.

## Background location and battery

- **Background updates:** while a ride is active, the watch app uses the `location` background mode with `allowsBackgroundLocationUpdates` and a `CLBackgroundActivitySession` (watchOS 10+), so recording can continue when you lower your wrist. Apple's headers document these APIs for watchOS. Whether watchOS keeps delivering fixes for a full ride on your watch **has not been tested on a device yet**.
- **Safety check:** the app checks that the background mode is present before enabling it. If it isn't, it falls back to foreground-only tracking instead of crashing.
- **Watch screen:** watchOS can still return to the watch face. Recording continues in the background, but the ScooterRide screen isn't kept in front.
- **Battery:** continuous GPS is among the most power-hungry things a watch does. Expect noticeably faster drain during rides, especially with **Precise GPS** on. No battery measurements have been made yet.
- **Saving battery:**
  - Turn **Precise GPS** off (about 10 m accuracy instead of best).
  - Pause when stopped for a while; GPS is off while paused.
  - End rides promptly.

## Known limitations

- **Speeds are GPS estimates.** They lag behind and differ from the scooter's speedometer, especially at low speed, under trees or between tall buildings.
- **Apple's workout detection** is out of the app's control (see above).
- **No scooter telemetry.** Earlier read-only Bluetooth investigation of this owner's US E3 Pro found only:
  - a proprietary Nordic UART data channel, undocumented and probably encrypted
  - a standard PnP ID
  - no standard battery, firmware or speed data
  
  Phase 3 will offer only a discovery screen for standard, exposed information. It won't connect automatically or change settings. No firmware flashing, speed-limit changes or safety-feature changes, ever.
- **Not yet built:**
  - iPhone history, sync and Siri Shortcuts (Phase 2)
  - automatic detection (Phase 3)
- **App icons** are placeholders.
- **Physical-device validation has not been done yet.** See *Testing status*.

## Testing status (only results that actually ran)

Phase 1, 2026-11-09, on a Mac mini (Apple M4, macOS 27.0.1, Xcode 26.6, Swift 6.3.3):

| Check | Result |
|---|---|
| `scripts/test.sh`: 32 RideKit unit tests in 6 suites (synthetic GPS data) | **Passed**, no warnings |
| `xcodebuild`: watchOS app for the watchOS Simulator | **Succeeded**, no compiler warnings |
| `xcodebuild`: iOS app with embedded watch app, iOS Simulator | **Succeeded**, no compiler warnings |
| `xcodebuild`: iOS + watch apps for devices (compile only, `CODE_SIGNING_ALLOWED=NO`) | **Succeeded**. Watch binary is `arm64_32 arm64` |
| Built watch `Info.plist` | Verified: `UIBackgroundModes = [location]`, location usage text, `WKCompanionAppBundleIdentifier`, minimum watchOS 10.0 |
| Watch app on the Apple Watch Ultra 3 (49 mm) **simulator**, watchOS 26.5 | Installed, launched, still running after 6 s, no crash report. Start screen rendered correctly (screenshot) |

**Physical device, 2026-11-09:**

| Check | Result |
|---|---|
| Install on the owner's **Apple Watch Ultra 2 (watchOS 27.2)** from Xcode 26.6 with the Personal Team, over Wi-Fi. Developer Mode had to be enabled on iPhone and watch first | **Installed**: `ScooterRide 0.1 (1)`, confirmed with `devicectl device info apps` |
| App launch on the watch | **Running**, confirmed with `devicectl device info processes`. The owner confirmed it opened |
| Test recording 1: 67 s, owner essentially stationary (track stayed within 6.9 m of the start). Ride file copied off the watch with `devicectl device copy from`; analyzed as aggregates only | 57 fixes at 1 Hz (largest gap 6 s, during GPS warm-up). 0 fixes rejected. Median accuracy 2.9 m (90th percentile 9.3 m). Doppler speed on 54 of 57 fixes. Raw point-to-point jitter of 41 m was correctly recorded as **0 m distance**. Max 1.4 mph. Saved and listed correctly. **Not a test of moving rides or wrist-down recording** |

**Found in testing:** the first accepted fix was timestamped 0.4 s before Start. Planned fix: ignore fixes timestamped before the ride (or resume) started.

**Not yet done:**
- the location permission prompt on the device
- recording a real ride
- background recording with the wrist lowered
- battery impact
- comparing GPS speed with the scooter's speedometer
- the iPhone app on the iPhone 16 Pro Max
- tapping Start Ride in the simulator, or replaying a simulated route

### Troubleshooting Developer Mode on Apple Watch

The watch's Developer Mode switch appears only after Xcode connects to the watch. Xcode reaches the watch **over Wi-Fi**, not through the iPhone's cable. If it's missing:
1. Turn on Developer Mode on the iPhone first. Connect it by cable, then go to Settings → Privacy & Security → Developer Mode.
2. Put the watch on the same Wi-Fi network as the Mac, and keep it awake and unlocked.
3. Open Xcode → Window → Devices and Simulators and wait for the watch to connect.
4. Restart the Mac, iPhone and watch if it stays unavailable.
