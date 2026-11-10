#!/bin/zsh
# SIMULATOR-ONLY end-to-end check of Apple Watch -> iPhone ride sync, using a SYNTHETIC ride.
# Requires a prior `scripts/build.sh` (simulator products) and an iPhone+Watch simulator pair.
#   1. boots a paired iPhone + Apple Watch simulator
#   2. installs both apps and places one synthetic finished ride in the watch app's storage
#   3. launches both apps and waits for the ride to appear on the iPhone and the
#      iPhone's acknowledgement to reach the watch
# It does not exercise real GPS, real devices or deletion.
set -uo pipefail
cd "${0:A:h}/.."

PRODUCTS=.build/DerivedData/Build/Products
PHONE_APP=$PRODUCTS/Debug-iphonesimulator/ScooterRide.app
WATCH_APP=$PRODUCTS/Debug-watchsimulator/ScooterRideWatch.app
PHONE_ID=com.saipraneethmedisetti.ScooterRide
WATCH_ID=$PHONE_ID.watchkitapp
TIMEOUT=${TIMEOUT:-90}

[[ -d $PHONE_APP && -d $WATCH_APP ]] || { echo "Build first: scripts/build.sh"; exit 2; }

read -r PAIR WATCH PHONE NAMES <<<"$(xcrun simctl list pairs available -j | /usr/bin/python3 -I -c '
import json, sys
pairs = json.load(sys.stdin)["pairs"]
for pid, p in pairs.items():
    print(pid, p["watch"]["udid"], p["phone"]["udid"], (p["watch"]["name"] + " + " + p["phone"]["name"]).replace(" ", "_"))
    break
')"
[[ -n ${PAIR:-} ]] || { echo "No available iPhone+Watch simulator pair."; exit 2; }
echo "Pair: ${NAMES//_/ }"

xcrun simctl boot "$PHONE" 2>/dev/null; xcrun simctl boot "$WATCH" 2>/dev/null
xcrun simctl bootstatus "$PHONE" -b >/dev/null; xcrun simctl bootstatus "$WATCH" -b >/dev/null
xcrun simctl install "$PHONE" "$PHONE_APP" && xcrun simctl install "$WATCH" "$WATCH_APP" || exit 1

WATCH_DATA=$(xcrun simctl get_app_container "$WATCH" "$WATCH_ID" data)
RIDES="$WATCH_DATA/Library/Application Support/Rides"
mkdir -p "$RIDES"
ID=$(/usr/bin/python3 -I - "$RIDES" <<'PY'
import json, sys, uuid, math
from datetime import datetime, timedelta, timezone
# SYNTHETIC ride: 120 s due north at 6 m/s near Apple Park. Not a real recording.
rid = str(uuid.uuid4()).upper()
t0 = datetime(2026, 11, 9, 18, 0, 0, tzinfo=timezone.utc)
iso = lambda t: t.isoformat(timespec="milliseconds").replace("+00:00", "Z")
m_per_deg = 6371008.8 * math.pi / 180
route = [{"segment": 0, "estimatedSpeed": 6.0,
          "sample": {"timestamp": iso(t0 + timedelta(seconds=i)), "latitude": 37.3349 + 6 * i / m_per_deg,
                     "longitude": -122.0090, "horizontalAccuracy": 5.0, "speed": 6.0, "speedAccuracy": 0.5}}
         for i in range(121)]
ride = {"schemaVersion": 1, "id": rid, "source": "watch", "startDate": iso(t0), "endDate": iso(t0 + timedelta(seconds=120)),
        "intervals": [{"start": iso(t0), "end": iso(t0 + timedelta(seconds=120))}], "route": route,
        "distanceMeters": 720.0, "maxSpeedMetersPerSecond": 6.0, "acceptedSampleCount": 121,
        "rejectedSampleCounts": {}, "recovered": False}
json.dump(ride, open(f"{sys.argv[1]}/ride-{rid}.json", "w"))
print(rid)
PY
)
echo "Synthetic ride on watch: $ID"

xcrun simctl launch "$PHONE" "$PHONE_ID" >/dev/null
xcrun simctl launch "$WATCH" "$WATCH_ID" >/dev/null

PHONE_DATA=$(xcrun simctl get_app_container "$PHONE" "$PHONE_ID" data)
RECEIVED=0; ACKED=0
for (( t = 0; t < TIMEOUT; t += 3 )); do
  [[ -f "$PHONE_DATA/Library/Application Support/Rides/ride-$ID.json" ]] && RECEIVED=1
  grep -q "$ID" "$RIDES/sync-state.json" 2>/dev/null && ACKED=1
  (( RECEIVED && ACKED )) && break
  sleep 3
done
echo "Ride on iPhone: $([[ $RECEIVED == 1 ]] && echo YES || echo NO) · acknowledged on watch: $([[ $ACKED == 1 ]] && echo YES || echo NO) (after ~${t}s)"

xcrun simctl io "$PHONE" screenshot /tmp/scooterride-phone-history.png >/dev/null 2>&1 && echo "iPhone screenshot: /tmp/scooterride-phone-history.png"
(( RECEIVED && ACKED )) && exit 0 || exit 1
