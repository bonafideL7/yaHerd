#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/yaHerd/PrivacyInfo.xcprivacy"
SOURCE_ROOT="$ROOT/yaHerd"

fail() {
  echo "Privacy verification failed: $*" >&2
  exit 1
}

[[ -f "$MANIFEST" ]] || fail "missing yaHerd/PrivacyInfo.xcprivacy"

plutil -lint "$MANIFEST" >/dev/null || fail "PrivacyInfo.xcprivacy is not a valid property list"

manifest_declares_category() {
  local category="$1"

  python3 - "$MANIFEST" "$category" <<'PYTHON'
import plistlib
import sys

manifest_path, expected_category = sys.argv[1:]
with open(manifest_path, "rb") as stream:
    manifest = plistlib.load(stream)

entries = manifest.get("NSPrivacyAccessedAPITypes", [])
if not isinstance(entries, list):
    raise SystemExit(1)

for entry in entries:
    if isinstance(entry, dict) and entry.get("NSPrivacyAccessedAPIType") == expected_category:
        raise SystemExit(0)

raise SystemExit(1)
PYTHON
}

manifest_declares_reason_for_category() {
  local category="$1"
  local reason="$2"

  python3 - "$MANIFEST" "$category" "$reason" <<'PYTHON'
import plistlib
import sys

manifest_path, expected_category, expected_reason = sys.argv[1:]
with open(manifest_path, "rb") as stream:
    manifest = plistlib.load(stream)

entries = manifest.get("NSPrivacyAccessedAPITypes", [])
if not isinstance(entries, list):
    raise SystemExit(1)

for entry in entries:
    if not isinstance(entry, dict):
        continue
    if entry.get("NSPrivacyAccessedAPIType") != expected_category:
        continue

    reasons = entry.get("NSPrivacyAccessedAPITypeReasons", [])
    if isinstance(reasons, list) and expected_reason in reasons:
        raise SystemExit(0)

raise SystemExit(1)
PYTHON
}

require_manifest_entry() {
  local category="$1"
  local reason="$2"
  local description="$3"
  local pattern="$4"

  if grep -R -E -q --include='*.swift' "$pattern" "$SOURCE_ROOT"; then
    manifest_declares_category "$category" \
      || fail "$description is used but $category is not declared"
    manifest_declares_reason_for_category "$category" "$reason" \
      || fail "$description is used but approved reason $reason is not declared for $category"
  fi
}

# Required-reason APIs currently used by yaHerd.
require_manifest_entry \
  "NSPrivacyAccessedAPICategoryUserDefaults" \
  "CA92.1" \
  "UserDefaults" \
  'UserDefaults'

require_manifest_entry \
  "NSPrivacyAccessedAPICategoryFileTimestamp" \
  "C617.1" \
  "file timestamp metadata" \
  'contentModificationDateKey|creationDateKey|fileModificationDate'

# Guard the remaining Apple required-reason API categories so new usage cannot be
# introduced without an explicit privacy-manifest decision.
if grep -R -E -q --include='*.swift' \
  'systemUptime|mach_absolute_time' "$SOURCE_ROOT"; then
  manifest_declares_category "NSPrivacyAccessedAPICategorySystemBootTime" \
    || fail "system boot-time API usage requires a declared approved reason"
fi

if grep -R -E -q --include='*.swift' \
  'volumeAvailableCapacityKey|volumeAvailableCapacityForImportantUsageKey|volumeAvailableCapacityForOpportunisticUsageKey|volumeTotalCapacityKey|systemFreeSize|systemSize|statfs\(|statvfs\(|fstatfs\(|fstatvfs\(' "$SOURCE_ROOT"; then
  manifest_declares_category "NSPrivacyAccessedAPICategoryDiskSpace" \
    || fail "disk-space API usage requires a declared approved reason"
fi

if grep -R -E -q --include='*.swift' 'activeInputModes' "$SOURCE_ROOT"; then
  manifest_declares_category "NSPrivacyAccessedAPICategoryActiveKeyboards" \
    || fail "active-keyboard API usage requires a declared approved reason"
fi

echo "Privacy manifest verification passed."
