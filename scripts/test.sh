#!/bin/zsh
# Runs the RideKit unit tests (speed, distance, session state, GPS filtering, persistence).
# All GPS data in the tests is synthetic.
set -euo pipefail
cd "${0:A:h}/../Packages/RideKit"
swift test "$@"
