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

manifest_dump="$(plutil -p "$MANIFEST")"

require_manifest_entry() {
  local category="$1"
  local reason="$2"
  local description="$3"
  local pattern="$4"

  if grep -R -E -q --include='*.swift' "$pattern" "$SOURCE_ROOT"; then
    grep -F -q "$category" <<<"$manifest_dump" \
      || fail "$description is used but $category is not declared"
    grep -F -q "$reason" <<<"$manifest_dump" \
      || fail "$description is used but approved reason $reason is not declared"
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
  grep -F -q "NSPrivacyAccessedAPICategorySystemBootTime" <<<"$manifest_dump" \
    || fail "system boot-time API usage requires a declared approved reason"
fi

if grep -R -E -q --include='*.swift' \
  'volumeAvailableCapacityKey|volumeAvailableCapacityForImportantUsageKey|volumeAvailableCapacityForOpportunisticUsageKey|volumeTotalCapacityKey|systemFreeSize|systemSize|statfs\(|statvfs\(|fstatfs\(|fstatvfs\(' "$SOURCE_ROOT"; then
  grep -F -q "NSPrivacyAccessedAPICategoryDiskSpace" <<<"$manifest_dump" \
    || fail "disk-space API usage requires a declared approved reason"
fi

if grep -R -E -q --include='*.swift' 'activeInputModes' "$SOURCE_ROOT"; then
  grep -F -q "NSPrivacyAccessedAPICategoryActiveKeyboards" <<<"$manifest_dump" \
    || fail "active-keyboard API usage requires a declared approved reason"
fi

echo "Privacy manifest verification passed."
