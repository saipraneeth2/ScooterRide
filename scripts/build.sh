#!/bin/zsh
# Builds every configuration we can check without a signing identity.
#   scripts/build.sh            -> simulator builds + device compile (no signing)
# Exit code is non-zero if any build fails.
set -uo pipefail
cd "${0:A:h}/.."

PROJECT=ScooterRide.xcodeproj
DERIVED=.build/DerivedData
FAILED=0

build() {
  local label="$1"; shift
  echo "=== $label"
  local log; log=$(mktemp)
  if xcodebuild -project "$PROJECT" -derivedDataPath "$DERIVED" "$@" build >"$log" 2>&1; then
    echo "BUILD SUCCEEDED"
  else
    echo "BUILD FAILED"; FAILED=1
  fi
  grep -E "(error|warning): " "$log" | grep -v "^ld: warning: .*search path" | sed -E 's#^.*/ScooterRide/##' | sort -u | head -40
  rm -f "$log"
}

build "watchOS app, Simulator" -scheme ScooterRideWatch -destination "generic/platform=watchOS Simulator"
build "iOS app + embedded watch app, Simulator" -scheme ScooterRide -destination "generic/platform=iOS Simulator"
build "iOS app + embedded watch app, device (compile only, no signing)" -scheme ScooterRide -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO

exit $FAILED
