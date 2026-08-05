#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

presentation_path="yaHerd/App/Recovery/RecoveryModeScenePresentation.swift"
app_path="yaHerd/App/yaHerdApp.swift"
recovery_root="yaHerd/App/Recovery"

if [[ ! -f "$presentation_path" ]]; then
  echo "Missing scene-local recovery presentation: $presentation_path" >&2
  exit 1
fi

if [[ -e "$recovery_root/RecoveryModeBannerOverlay.swift" ]]; then
  echo "The obsolete RecoveryModeBannerOverlay.swift file must not be restored." >&2
  exit 1
fi

prohibited_patterns=(
  "import UIKit"
  "UIWindow"
  "UIApplication.shared.connectedScenes"
  "RecoveryModeBannerOverlay.shared"
)

for pattern in "${prohibited_patterns[@]}"; do
  if grep -RFn --include='*.swift' "$pattern" "$recovery_root" "$app_path"; then
    echo "Recovery presentation must remain inside each SwiftUI scene hierarchy: prohibited pattern '$pattern'." >&2
    exit 1
  fi
done

required_fragments=(
  "RecoveryModeScenePresentationModifier"
  ".safeAreaInset(edge: .top, spacing: 0)"
  ".sheet(isPresented: \$controller.isPresentingCenter)"
)

for fragment in "${required_fragments[@]}"; do
  if ! grep -Fq "$fragment" "$presentation_path"; then
    echo "Scene-local recovery presentation is missing required fragment: $fragment" >&2
    exit 1
  fi
done

if ! grep -Fq ".recoveryModeScenePresentation(" "$app_path"; then
  echo "yaHerdApp.swift must install recovery presentation at the SwiftUI scene root." >&2
  exit 1
fi

echo "Recovery presentation checks passed."
