#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT_FILE="yaHerd.xcodeproj/project.pbxproj"
DERIVED_DATA_PATH="$ROOT_DIR/.build/ConcurrencyDerivedData"

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
import sys

failures = []

for path in Path('yaHerd/App').rglob('*.swift'):
    source = path.read_text()
    for match in re.finditer(r'notifications\s*\([^)]*object\s*:\s*([^,\n)]+)', source, re.DOTALL):
        if match.group(1).strip() != 'nil':
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
            f'{path}:{line}: {match.group(1)} must be declared nonisolated so EnvironmentKey.defaultValue can construct it without target-wide MainActor isolation'
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

repair_root = Path('yaHerd/Data/Repositories')
for path in repair_root.glob('DeterministicSwiftDataPublicIDRepair*.swift'):
    text = path.read_text()
    for match in re.finditer(r'\.(?:map|compactMap|filter)\s*\{(?:(?!\n\s*\}).){0,1600}?\bplan\.', text, re.DOTALL):
        line = text.count('\n', 0, match.start()) + 1
        failures.append(
            f'{path}:{line}: RepairPlan must not be captured by map/filter/compactMap closures; iterate on the model actor instead'
        )
    for match in re.finditer(
        r'evidenceMatches\s*:\s*\{(?:(?!\n\s*\}).){0,800}?fieldCheck(?:Pasture|Animal|Finding)\w*Matches\((?:session|check|finding)\b',
        text,
        re.DOTALL,
    ):
        line = text.count('\n', 0, match.start()) + 1
        failures.append(
            f'{path}:{line}: SwiftData field-check models must not be captured by evidence-matching closures'
        )

if failures:
    print(
        'Swift concurrency architecture checks failed:',
        file=sys.stderr,
    )
    print('\n'.join(failures), file=sys.stderr)
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
  echo 'Static concurrency policy checks passed. xcodebuild is unavailable; compile verification skipped.'
  exit 0
fi

xcodebuild -version
xcrun swiftc --version

setting_value() {
  local settings="$1"
  local key="$2"
  printf '%s\n' "$settings" | awk -F ' = ' -v key="$key" '
    {
      lhs = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
      if (lhs == key) {
        print $2
        exit
      }
    }
  '
}

assert_effective_setting() {
  local target="$1"
  local configuration="$2"
  local key="$3"
  local expected="$4"
  local settings="$5"
  local actual
  actual="$(setting_value "$settings" "$key")"
  if [[ "$actual" != "$expected" ]]; then
    echo "$target $configuration effective $key is '${actual:-<unset>}', expected '$expected'." >&2
    exit 1
  fi
}

verify_target_settings() {
  local target="$1"
  local configuration="$2"
  local settings
  settings="$(xcodebuild \
    -project yaHerd.xcodeproj \
    -target "$target" \
    -configuration "$configuration" \
    -sdk iphonesimulator \
    CODE_SIGNING_ALLOWED=NO \
    -showBuildSettings)"

  assert_effective_setting "$target" "$configuration" SWIFT_VERSION 6.0 "$settings"
  assert_effective_setting "$target" "$configuration" SWIFT_STRICT_CONCURRENCY complete "$settings"
  assert_effective_setting "$target" "$configuration" SWIFT_TREAT_WARNINGS_AS_ERRORS YES "$settings"
  assert_effective_setting "$target" "$configuration" SWIFT_APPROACHABLE_CONCURRENCY YES "$settings"

  local default_isolation
  default_isolation="$(setting_value "$settings" SWIFT_DEFAULT_ACTOR_ISOLATION)"
  if [[ "$default_isolation" == "MainActor" ]]; then
    echo "$target $configuration resolves SWIFT_DEFAULT_ACTOR_ISOLATION to MainActor; explicit isolation is required." >&2
    exit 1
  fi
}

for configuration in Debug Release; do
  verify_target_settings yaHerd "$configuration"
  verify_target_settings yaHerdTests "$configuration"
done

# Prove that the selected compiler is enforcing an unambiguously unsafe Swift 6
# actor-boundary access. The actor retains the non-Sendable reference, so the
# value cannot safely be exposed to another isolation domain.
SMOKE_DIR="$(mktemp -d)"
SMOKE_LOG="$SMOKE_DIR/compiler-smoke.log"
cat >"$SMOKE_DIR/ConcurrencyViolation.swift" <<'SWIFT'
final class NonSendableReference {
    var value = 0
}

actor Holder {
    let stored = NonSendableReference()
}

func intentionallyInvalidRead(from holder: Holder) async {
    let value = await holder.stored
    value.value += 1
}
SWIFT

set +e
xcrun swiftc \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  -typecheck \
  "$SMOKE_DIR/ConcurrencyViolation.swift" >"$SMOKE_LOG" 2>&1
smoke_status=$?
set -e

if [[ "$smoke_status" -eq 0 ]]; then
  echo 'Swift compiler concurrency smoke test unexpectedly compiled an actor-retained non-Sendable boundary crossing.' >&2
  cat "$SMOKE_LOG" >&2
  rm -rf "$SMOKE_DIR"
  exit 1
fi
if ! grep -Eqi 'sending|data race|non-Sendable|Sendable|actor boundary|actor-isolated' "$SMOKE_LOG"; then
  echo 'Swift compiler rejected the concurrency smoke test, but not with a recognized concurrency diagnostic.' >&2
  cat "$SMOKE_LOG" >&2
  rm -rf "$SMOKE_DIR"
  exit 1
fi
rm -rf "$SMOKE_DIR"

echo 'Swift compiler strict-concurrency smoke test passed.'

rm -rf "$DERIVED_DATA_PATH"
mkdir -p "$(dirname "$DERIVED_DATA_PATH")"

BUILD_LOG="$(mktemp)"
trap 'rm -f "$BUILD_LOG"' EXIT

run_xcodebuild_gate() {
  local label="$1"
  shift

  : >"$BUILD_LOG"
  set +e
  xcodebuild \
    -quiet \
    -project yaHerd.xcodeproj \
    -scheme yaHerd \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    SWIFT_VERSION=6.0 \
    SWIFT_STRICT_CONCURRENCY=complete \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
    SWIFT_SUPPRESS_WARNINGS=NO \
    "$@" >"$BUILD_LOG" 2>&1
  local build_status=$?
  set -e

  if [[ "$build_status" -ne 0 ]]; then
    echo "$label failed:" >&2
    grep -E -i 'error:|warning:|fatal|signal|killed|command .* failed|failed to|unable to|BUILD FAILED|sending .* risks causing data races' "$BUILD_LOG" | tail -n 160 >&2 || true
    tail -n 80 "$BUILD_LOG" >&2
    exit "$build_status"
  fi

  if grep -E -i 'warning:|sending .* risks causing data races' "$BUILD_LOG" >/dev/null; then
    echo "$label emitted warnings despite SWIFT_TREAT_WARNINGS_AS_ERRORS=YES:" >&2
    grep -E -i 'warning:|sending .* risks causing data races' "$BUILD_LOG" | tail -n 160 >&2
    exit 1
  fi

  echo "$label passed."
}

run_xcodebuild_gate \
  'Debug iOS Simulator build' \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build

run_xcodebuild_gate \
  'Release iOS Simulator build' \
  -configuration Release \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build

run_xcodebuild_gate \
  'Debug build-for-testing' \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build-for-testing

run_xcodebuild_gate \
  'Release iOS device build' \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  build

echo 'Swift 6 concurrency verification passed.'
