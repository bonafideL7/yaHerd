#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT_FILE="yaHerd.xcodeproj/project.pbxproj"

require_setting() {
  local pattern="$1"
  local expected_count="$2"
  local actual_count
  actual_count="$(grep -c "$pattern" "$PROJECT_FILE" || true)"
  if [[ "$actual_count" -lt "$expected_count" ]]; then
    echo "Missing required concurrency setting: $pattern (found $actual_count, expected at least $expected_count)" >&2
    exit 1
  fi
}

require_setting 'SWIFT_VERSION = 6.0;' 4
require_setting 'SWIFT_STRICT_CONCURRENCY = complete;' 2
require_setting 'SWIFT_TREAT_WARNINGS_AS_ERRORS = YES;' 2

if grep -q 'SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;' "$PROJECT_FILE"; then
  echo 'Module-wide MainActor default isolation is prohibited; isolate UI and persistence boundaries explicitly.' >&2
  exit 1
fi

if grep -R --line-number --include='*.swift' '@unchecked Sendable' yaHerd; then
  echo '@unchecked Sendable is prohibited in application sources.' >&2
  exit 1
fi

if grep -R --line-number --include='*.swift' -E '\bNS(Lock|RecursiveLock)\b' yaHerd; then
  echo 'Lock-backed mutable state is prohibited; use actor isolation.' >&2
  exit 1
fi

if grep -R --line-number --include='*.swift' 'Task\.detached' yaHerd; then
  echo 'Task.detached requires an explicit architecture review and is currently prohibited.' >&2
  exit 1
fi

if grep -R --line-number --include='*.swift' -E '\[[^]]*cloudStore[^]]*\]' yaHerd/App; then
  echo 'NSUbiquitousKeyValueStore must not be captured by a Task because its Sendable conformance is unavailable.' >&2
  exit 1
fi

actor_default_arguments="$(grep -R --line-number --include='*.swift' -E 'ApplicationSettings[[:space:]]*=[[:space:]]*ApplicationSettings\(|AppSettingsSyncing[[:space:]]*=[[:space:]]*AppSettingsSynchronizer\(|CloudKitSchemaChecking[[:space:]]*=[[:space:]]*CloudKitSchemaChecker\(' yaHerd || true)"
if [[ -n "$actor_default_arguments" ]]; then
  echo "$actor_default_arguments" >&2
  echo 'Main-actor dependencies must not be constructed in default argument expressions; use an explicit @MainActor convenience initializer.' >&2
  exit 1
fi

python3 - <<'PYTHON'
from pathlib import Path
import re

failures = []

for path in Path('yaHerd/App').rglob('*.swift'):
    source = path.read_text()
    for match in re.finditer(r'notifications\s*\([^)]*object\s*:\s*([^,\n)]+)', source, re.DOTALL):
        source_argument = match.group(1).strip()
        if source_argument != 'nil':
            line = source.count('\n', 0, match.start()) + 1
            failures.append(
                f'{path}:{line}: async NotificationCenter source filters must be nil unless the source type is Sendable'
            )
for path in Path('yaHerd/Domain/UseCases').rglob('*.swift'):
    lines = path.read_text().splitlines()
    for index, line in enumerate(lines):
        if not re.match(r'^(struct|final class|class)\s+\w*UseCase\b', line):
            continue
        previous = next(
            (lines[candidate].strip() for candidate in range(index - 1, -1, -1) if lines[candidate].strip()),
            ''
        )
        if previous != '@MainActor':
            failures.append(f'{path}:{index + 1}: {line}')

for relative_path in (
    'yaHerd/Domain/Services/PastureInputValidator.swift',
    'yaHerd/Domain/Services/PastureGroupInputValidator.swift',
):
    path = Path(relative_path)
    if not re.search(r'@MainActor\s*\nstruct\s+', path.read_text()):
        failures.append(f'{path}: repository-backed validator must be @MainActor')

environment_root = Path('yaHerd/Presentation/Support/Environment')
for path in environment_root.glob('*Dependencies.swift'):
    text = path.read_text()
    for match in re.finditer(r'^(?:@MainActor\s*)?struct\s+(\w+Dependencies)\b', text, re.MULTILINE):
        line = text.count('\n', 0, match.start()) + 1
        failures.append(
            f'{path}:{line}: {match.group(1)} must be declared nonisolated so EnvironmentKey.defaultValue can construct it under MainActor default isolation'
        )

for path in environment_root.glob('*.swift'):
    text = path.read_text()
    for match in re.finditer(r'^private struct (Missing\w+):[^\n]+\{', text, re.MULTILINE):
        body_start = match.end()
        next_declaration = re.search(r'^private (?:struct|final class|class|enum) ', text[body_start:], re.MULTILINE)
        body_end = body_start + next_declaration.start() if next_declaration else len(text)
        body = text[body_start:body_end]
        if not re.search(r'\bnonisolated\s+init\s*\(\s*environmentFallback\s+_:', body):
            line = text.count('\n', 0, match.start()) + 1
            failures.append(
                f'{path}:{line}: {match.group(1)} must provide nonisolated init() for EnvironmentKey default construction'
            )

if failures:
    print('Main-actor repository orchestration and environment fallbacks must remain explicitly isolated:', file=__import__('sys').stderr)
    print('\n'.join(failures), file=__import__('sys').stderr)
    raise SystemExit(1)
PYTHON

unisolated_task_calls="$(grep -R --line-number --include='*.swift' -E 'Task[[:space:]]*\{' yaHerd \
  | grep -v -E 'Task[[:space:]]*\{[[:space:]]*(@MainActor|@concurrent)' || true)"
if [[ -n "$unisolated_task_calls" ]]; then
  echo "$unisolated_task_calls" >&2
  echo 'Every unstructured Task must declare its executor explicitly.' >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'Static concurrency policy checks passed. xcodebuild is unavailable; compile gate skipped.'
  exit 0
fi

BUILD_LOG="$(mktemp)"
TEST_LOG="$(mktemp)"
RESULT_BUNDLE="$ROOT_DIR/.build/PersistenceTests.xcresult"
rm -rf "$RESULT_BUNDLE"
trap 'rm -f "$BUILD_LOG" "$TEST_LOG"' EXIT

set +e
xcodebuild \
  -quiet \
  -project yaHerd.xcodeproj \
  -scheme yaHerd \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing >"$BUILD_LOG" 2>&1
build_status=$?
set -e

if [[ "$build_status" -ne 0 ]]; then
  echo 'Swift 6 build failed:' >&2
  grep -E -i 'error:|fatal|signal|killed|command .* failed|failed to|unable to|BUILD FAILED|Testing failed' "$BUILD_LOG" | tail -n 120 >&2 || true
  echo 'Final build log:' >&2
  tail -n 60 "$BUILD_LOG" >&2
  exit "$build_status"
fi

cat "$BUILD_LOG"

SIMULATOR_ID="$(xcrun simctl list devices available -j | python3 -c '
import json
import sys

devices = json.load(sys.stdin).get("devices", {})
for runtime_devices in devices.values():
    for device in runtime_devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit(1)
')"

if [[ -z "$SIMULATOR_ID" ]]; then
  echo 'No available iPhone simulator was found for persistence tests.' >&2
  exit 1
fi

xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b

PERSISTENCE_TEST_SUITES=(
  AnimalListViewModelReloadTests
  ApplicationMutationCenterTests
  HerdSharingBridgeImportBoundaryTests
  HerdSharingBridgeReliabilityTests
  HerdSharingCoreDataModelCachingTests
  HerdSharingDeletionTombstoneIdentityTests
  HerdSharingImportCommitBoundaryTests
  HerdSharingRepositoryTests
  SwiftDataHerdSharingActorDuplicateIDPagingTests
  SwiftDataHerdSharingActorRelationshipScopeTests
  SwiftDataHerdSharingActorTests
  SwiftDataPublicIDRepairServiceTests
  SwiftDataReadModelActorPaginationTests
  SwiftDataReadModelActorPasturePaginationTests
  SwiftDataReadModelActorTests
)
TEST_SELECTION_ARGS=()
for suite in "${PERSISTENCE_TEST_SUITES[@]}"; do
  if [[ ! -f "yaHerdTests/$suite.swift" ]]; then
    echo "Configured persistence test suite source is missing: yaHerdTests/$suite.swift" >&2
    exit 1
  fi
  TEST_SELECTION_ARGS+=("-only-testing:yaHerdTests/$suite")
done

set +e
xcodebuild \
  -quiet \
  -project yaHerd.xcodeproj \
  -scheme yaHerd \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -resultBundlePath "$RESULT_BUNDLE" \
  test-without-building \
  "${TEST_SELECTION_ARGS[@]}" >"$TEST_LOG" 2>&1
test_status=$?
set -e

if [[ "$test_status" -ne 0 ]]; then
  echo 'Persistence-focused tests failed:' >&2
  grep -E -i 'error:|failed|failure|fatal|signal|killed|uncaught|assert' "$TEST_LOG" | tail -n 160 >&2 || true
  echo 'Result bundle summary:' >&2
  xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" >&2 || true
  echo 'Recent yaHerd simulator logs:' >&2
  xcrun simctl spawn "$SIMULATOR_ID" log show \
    --last 10m \
    --style compact \
    --predicate 'process == "yaHerd" OR process == "xctest"' 2>&1 \
    | tail -n 300 >&2 || true
  echo 'Recent crash reports:' >&2
  find "$HOME/Library/Logs/DiagnosticReports" -type f \
    \( -name 'yaHerd*.ips' -o -name 'yaHerd*.crash' -o -name 'xctest*.ips' -o -name 'xctest*.crash' \) \
    -mmin -15 -print -exec tail -n 240 {} \; >&2 || true
  echo 'Final test log:' >&2
  tail -n 100 "$TEST_LOG" >&2
  exit "$test_status"
fi

cat "$TEST_LOG"
