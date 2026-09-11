#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_SOURCE_DIR="$ROOT_DIR/yaHerdTests"
DERIVED_DATA_PATH="$ROOT_DIR/.build/TestDerivedData"

if [[ ! -d "$TEST_SOURCE_DIR" ]] || ! find "$TEST_SOURCE_DIR" -type f -name '*.swift' -print -quit | grep -q .; then
  echo 'yaHerdTests has no Swift test sources. Release verification must not pass with an empty test target.' >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'xcodebuild is unavailable; test execution cannot be verified.' >&2
  exit 1
fi

SIMULATOR_UDID="$(python3 - <<'PYTHON'
import json
import re
import subprocess

payload = json.loads(
    subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'available', '-j'],
        text=True,
    )
)

candidates = []
for runtime, devices in payload.get('devices', {}).items():
    match = re.search(r'iOS-(\d+)(?:-(\d+))?', runtime)
    if match is None:
        continue
    version = (int(match.group(1)), int(match.group(2) or 0))
    if version < (26, 0):
        continue
    for device in devices:
        if not device.get('isAvailable', True):
            continue
        if not device.get('name', '').startswith('iPhone'):
            continue
        candidates.append((version, device['name'], device['udid']))

if candidates:
    candidates.sort(key=lambda item: (item[0], item[1]), reverse=True)
    print(candidates[0][2])
PYTHON
)"

if [[ -z "$SIMULATOR_UDID" ]]; then
  echo 'No available iOS 26+ iPhone simulator was found for unit tests.' >&2
  xcrun simctl list devices available >&2 || true
  exit 1
fi

echo "Running yaHerdTests on simulator $SIMULATOR_UDID"
xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b

mkdir -p "$(dirname "$DERIVED_DATA_PATH")"
TEST_LOG="$(mktemp)"
trap 'rm -f "$TEST_LOG"' EXIT

set +e
xcodebuild \
  -quiet \
  -project yaHerd.xcodeproj \
  -scheme yaHerd \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  test >"$TEST_LOG" 2>&1
test_status=$?
set -e

if [[ "$test_status" -ne 0 ]]; then
  echo 'yaHerd unit tests failed:' >&2
  grep -E -i 'error:|warning:|failed|failure|fatal|signal|killed|Test Case|Test Suite|✘|Issue recorded' "$TEST_LOG" | tail -n 200 >&2 || true
  tail -n 100 "$TEST_LOG" >&2
  exit "$test_status"
fi

if ! grep -E -q 'Test Suite|Test run|✔|passed' "$TEST_LOG"; then
  echo 'xcodebuild returned success, but no executed test result was detected.' >&2
  tail -n 100 "$TEST_LOG" >&2
  exit 1
fi

echo 'yaHerd unit tests passed.'
