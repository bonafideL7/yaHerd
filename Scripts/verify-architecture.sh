#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PYTHON'
from pathlib import Path
import re
import sys

root = Path("yaHerd/Domain")
allowed_imports = {"Foundation"}
failures: list[str] = []

legacy_preferences_path = Path("yaHerd/App/Preferences/AppPreferences.swift")
if legacy_preferences_path.exists():
    legacy_preferences_source = legacy_preferences_path.read_text()
    legacy_declarations = re.findall(
        r"^\s*(?:protocol|class|final\s+class|struct|actor|enum|typealias)\s+"
        r"(?:AppPreferences|AppSettingsSyncing|AppSettingsSynchronizer|AppPreferenceKey|SyncedAppSettingKey)\b",
        legacy_preferences_source,
        re.MULTILINE,
    )
    if legacy_declarations:
        failures.append(
            f"{legacy_preferences_path}: legacy application-settings declarations must not be restored"
        )

for path in root.rglob("*.swift"):
    source = path.read_text()
    for line_number, line in enumerate(source.splitlines(), start=1):
        match = re.match(r"\s*import\s+([A-Za-z0-9_]+)", line)
        if match and match.group(1) not in allowed_imports:
            failures.append(
                f"{path}:{line_number}: Domain imports platform framework {match.group(1)}"
            )

    for match in re.finditer(r"\b(?:CK[A-Z][A-Za-z0-9_]*|NSManagedObject|ModelContext|SwiftUI\.View|UIViewController)\b", source):
        line_number = source.count("\n", 0, match.start()) + 1
        failures.append(
            f"{path}:{line_number}: Domain references platform type {match.group(0)}"
        )



app_source = Path("yaHerd/App/yaHerdApp.swift").read_text()
allowed_root_environment_values = {
    "appDataAccessMode",
    "recoveryModeController",
    "homeFeatureDependencies",
    "animalFeatureDependencies",
    "pastureFeatureDependencies",
    "fieldCheckFeatureDependencies",
    "workingSessionFeatureDependencies",
    "collaborationDependencies",
}
root_environment_values = re.findall(r"\.environment\(\\\.([A-Za-z0-9_]+)", app_source)
for environment_value in root_environment_values:
    if environment_value not in allowed_root_environment_values:
        failures.append(
            f"yaHerd/App/yaHerdApp.swift: root injects ungrouped environment dependency {environment_value}"
        )

if len(root_environment_values) > len(allowed_root_environment_values):
    failures.append(
        "yaHerd/App/yaHerdApp.swift: root dependency injection exceeds the approved feature-boundary values"
    )

if app_source.count(".environment(applicationSettings)") != 1:
    failures.append(
        "yaHerd/App/yaHerdApp.swift: inject exactly one observable ApplicationSettings service at the app root"
    )

legacy_dependency_keys = {
    "animalListRepository", "animalEditorRepository", "animalDetailRepository",
    "animalTimelineReader", "animalParentOptionReader", "animalHealthRecordAdder",
    "animalPregnancyCheckAdder", "pastureReferenceDataReader", "sampleDataSeeder",
    "pastureListRepository", "pastureCreateRepository", "pastureDetailRepository",
    "pastureGroupListRepository", "pastureGroupDetailRepository",
    "pastureGroupEditorRepository", "pastureReferenceReader", "animalPastureMover",
    "fieldCheckPastureArchiveWriter", "fieldCheckOverviewReader",
    "fieldCheckSessionSetupRepository", "fieldCheckSessionDetailRepository",
    "fieldCheckAnimalDetailRepository", "workingSessionsRepository",
    "workingSessionDetailRepository", "newWorkingSessionRepository",
    "workingCollectAnimalsRepository", "workingQueueRepository",
    "workingQueueItemEditingRepository", "workingChuteRepository",
    "workingFinishSessionRepository", "workingProtocolTemplatesRepository",
    "workingProtocolTemplateCreator", "workingProtocolTemplateEditorRepository",
    "workingAnimalSummaryReader", "workingProtocolTemplateReader",
    "dashboardRecordReader", "herdRepository", "herdSharingRepository",
    "cloudKitShareInvitationCoordinator", "cloudKitShareAdapter",
    "herdSharingSyncCoordinator", "herdCollaborationWritePolicy",
    "herdSharingConflictReviewStore", "syncDiagnosticsRepository",
}
for path in Path("yaHerd").rglob("*.swift"):
    source = path.read_text()
    for match in re.finditer(r"@Environment\(\\\.([A-Za-z0-9_]+)\)", source):
        if match.group(1) in legacy_dependency_keys:
            line_number = source.count("\n", 0, match.start()) + 1
            failures.append(
                f"{path}:{line_number}: inject feature dependencies through a feature container, not {match.group(1)}"
            )

feature_environment_root = Path("yaHerd/Presentation/Support/Environment")
feature_dependency_keys = set()
for path in feature_environment_root.glob("*.swift"):
    source = path.read_text()
    feature_dependency_keys.update(
        re.findall(r"var\s+([A-Za-z0-9_]+Dependencies)\s*:", source)
    )
required_feature_dependency_keys = {
    "homeFeatureDependencies",
    "animalFeatureDependencies",
    "pastureFeatureDependencies",
    "fieldCheckFeatureDependencies",
    "workingSessionFeatureDependencies",
    "collaborationDependencies",
}
missing_feature_dependency_keys = required_feature_dependency_keys - feature_dependency_keys
if missing_feature_dependency_keys:
    failures.append(
        "Missing feature dependency environment values: "
        + ", ".join(sorted(missing_feature_dependency_keys))
    )

settings_catalog_path = Path("yaHerd/App/Preferences/ApplicationSettingCatalog.swift")
known_setting_literals = {
    "syncMode",
    "allowHardDelete",
    "isDashboardEnabled",
    "targetAcresPerHeadDefault",
    "usableAcreagePercentDefault",
    "recentPastureIDs",
    "recentPastureNames",
    "homeDismissedSetupSuggestionIDs",
    "homeSetupSuggestionsExpanded",
    "settings.syncMode",
    "settings.allowHardDelete",
    "settings.dashboardEnabled",
    "settings.targetAcresPerHeadDefault",
    "settings.usableAcreagePercentDefault",
    "settings.recentPastureIDs",
    "settings.homeDismissedSetupSuggestionIDs",
    "settings.homeSetupSuggestionsExpanded",
    "settings.legacy.recentPastureNames",
}
for path in Path("yaHerd").rglob("*.swift"):
    source = path.read_text()
    if "@AppStorage" in source:
        line_number = source.count("\n", 0, source.index("@AppStorage")) + 1
        failures.append(
            f"{path}:{line_number}: use the typed ApplicationSettings service instead of @AppStorage"
        )

    if path == settings_catalog_path:
        continue

    for literal in known_setting_literals:
        match = re.search(rf'"{re.escape(literal)}"', source)
        if match:
            line_number = source.count("\n", 0, match.start()) + 1
            failures.append(
                f"{path}:{line_number}: application setting key {literal} must be defined only in ApplicationSettingCatalog"
            )

required_setting_cases = {
    "syncMode",
    "allowHardDelete",
    "dashboardEnabled",
    "targetAcresPerHeadDefault",
    "usableAcreagePercentDefault",
    "recentPastureIDs",
    "homeDismissedSetupSuggestionIDs",
    "homeSetupSuggestionsExpanded",
    "legacyRecentPastureNames",
}
catalog_source = settings_catalog_path.read_text()
catalog_cases = set(re.findall(r"^\s*case\s+(\w+)", catalog_source, re.MULTILINE))
missing_setting_cases = required_setting_cases - catalog_cases
if missing_setting_cases:
    failures.append(
        "ApplicationSettingCatalog is missing settings: " + ", ".join(sorted(missing_setting_cases))
    )



use_case_root = Path("yaHerd/Domain/UseCases")
for path in use_case_root.rglob("*.swift"):
    source = path.read_text()
    for declaration in re.finditer(r"\bstruct\s+(\w+UseCase)\b", source):
        type_name = declaration.group(1)
        execute_match = re.search(r"\bfunc\s+execute\s*\(", source[declaration.end():])
        if execute_match is None:
            continue

        function_start = declaration.end() + execute_match.start()
        body_start = source.find("{", function_start)
        if body_start == -1:
            continue

        depth = 0
        body_end = None
        for index in range(body_start, len(source)):
            character = source[index]
            if character == "{":
                depth += 1
            elif character == "}":
                depth -= 1
                if depth == 0:
                    body_end = index
                    break

        if body_end is None:
            continue

        body = source[body_start + 1:body_end]
        compact_body = re.sub(r"\s+", " ", body).strip()
        repository_calls = re.findall(
            r"\b[A-Za-z_][A-Za-z0-9_]*repository\.[A-Za-z_][A-Za-z0-9_]*\(",
            compact_body,
            flags=re.IGNORECASE,
        )
        has_control_flow = re.search(r"\b(?:guard|if|for|while|switch|defer)\b", compact_body)
        has_domain_collaborator = re.search(
            r"\b(?:[A-Za-z_][A-Za-z0-9_]*(?:Service|Policy|Validator)|[A-Z][A-Za-z0-9_]+Input)\(",
            compact_body,
        )
        pass_through = (
            len(repository_calls) == 1
            and compact_body.count("try ") == 1
            and not has_control_flow
            and not has_domain_collaborator
        )
        if pass_through:
            failures.append(
                f"{path}: {type_name} only forwards one repository call; inject the domain repository port directly or add real policy/orchestration"
            )

if failures:
    print("Architecture boundary checks failed:", file=sys.stderr)
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)

print("Architecture boundary checks passed.")
PYTHON
