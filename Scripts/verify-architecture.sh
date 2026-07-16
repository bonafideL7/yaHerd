#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PYTHON'
from pathlib import Path
import plistlib
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



navigation_state_path = Path("yaHerd/App/Navigation/AppNavigationState.swift")
main_tab_path = Path("yaHerd/Presentation/Views/Navigation/MainTabView.swift")
app_root_path = Path("yaHerd/App/yaHerdApp.swift")

if Path("yaHerd/App/Navigation/NavigationCoordinator.swift").exists():
    failures.append(
        "NavigationCoordinator.swift must not be restored; AppNavigationState owns actual stack state"
    )

for path in Path("yaHerd").rglob("*.swift"):
    source = path.read_text()
    if "globalPath" in source or "NavigationCoordinator" in source:
        failures.append(
            f"{path}: disconnected NavigationCoordinator/globalPath navigation is not allowed"
        )

if not navigation_state_path.exists():
    failures.append("Missing AppNavigationState.swift")
else:
    navigation_source = navigation_state_path.read_text()
    required_navigation_types = {
        "AppNavigationState",
        "HerdRouter",
        "WorkflowRouter",
        "HerdRoute",
        "WorkflowRoute",
        "AppNavigationSnapshot",
        "AppNavigationRequest",
    }
    for type_name in required_navigation_types:
        if not re.search(rf"\b(?:class|final\s+class|struct|enum)\s+{type_name}\b", navigation_source):
            failures.append(f"AppNavigationState.swift is missing {type_name}")

    for route_name in ("HerdRoute", "WorkflowRoute", "AppNavigationRequest"):
        declaration = re.search(rf"enum\s+{route_name}\s*:\s*([^{{]+)", navigation_source)
        if declaration is None or "Codable" not in declaration.group(1):
            failures.append(f"{route_name} must remain a typed Codable route")

main_tab_source = main_tab_path.read_text()
if len(main_tab_source.splitlines()) > 120:
    failures.append(
        "MainTabView.swift exceeds 120 lines; move navigation behavior into routers or feature roots"
    )
if "@State" in main_tab_source or "NavigationPath" in main_tab_source:
    failures.append(
        "MainTabView must not own navigation paths or modal/search workflow state"
    )
if 'Tab("Search"' in main_tab_source or "role: .search" in main_tab_source:
    failures.append(
        "Search must remain inside the single herd navigation hierarchy, not a duplicate tab tree"
    )

app_root_source = app_root_path.read_text()
project_source = Path("yaHerd.xcodeproj/project.pbxproj").read_text()


def plist_registers_yaherd_url_scheme(path: Path) -> bool:
    try:
        with path.open("rb") as file:
            plist = plistlib.load(file)
    except (OSError, plistlib.InvalidFileException):
        return False

    return any(
        isinstance(scheme, str) and scheme.casefold() == "yaherd"
        for url_type in plist.get("CFBundleURLTypes", [])
        if isinstance(url_type, dict)
        for scheme in url_type.get("CFBundleURLSchemes", [])
    )


info_plist_candidates = (
    Path("Info/Info.plist"),
    Path("Info.plist"),
    Path("yaHerd/Info.plist"),
)
url_scheme_registered_in_plist = any(
    plist_registers_yaherd_url_scheme(path)
    for path in info_plist_candidates
    if path.exists()
)

# Xcode may either use a checked-in Info.plist shared by Debug and Release,
# or generate the plist from per-configuration project settings. Accept both.
url_scheme_registered_in_generated_settings = (
    project_source.count("CFBundleURLSchemes") >= 2
    and len(re.findall(r"(?m)^\s*yaherd,?\s*$", project_source)) >= 2
)

if not (
    url_scheme_registered_in_plist
    or url_scheme_registered_in_generated_settings
):
    failures.append(
        "The yaHerd URL scheme must remain registered in the app Info.plist "
        "or in both generated app build configurations"
    )

for required_fragment in (
    '@SceneStorage("navigation.restoration.v1")',
    ".environment(navigation)",
    ".onOpenURL",
):
    if required_fragment not in app_root_source:
        failures.append(
            f"yaHerdApp.swift is missing navigation restoration/routing fragment: {required_fragment}"
        )



mutation_center_path = Path("yaHerd/App/Mutation/ApplicationMutationCenter.swift")
mutation_repository_path = Path("yaHerd/App/Mutation/MutationCoordinatingRepositories.swift")
home_view_path = Path("yaHerd/Presentation/Views/Home/HomeView.swift")

for required_path in (mutation_center_path, mutation_repository_path, home_view_path):
    if not required_path.exists():
        failures.append(f"Missing automatic application mutation component: {required_path}")

manual_home_refresh_fragments = {
    "homeRefreshToken",
    "refreshHome()",
    "refreshToken:",
}
for path in Path("yaHerd").rglob("*.swift"):
    source = path.read_text()
    for fragment in manual_home_refresh_fragments:
        if fragment in source:
            failures.append(
                f"{path}: manual home refresh fragment {fragment!r} is prohibited; publish a successful mutation instead"
            )

if home_view_path.exists():
    home_view_source = home_view_path.read_text()
    if ".task(id:" in home_view_source or ".onAppear" in home_view_source:
        failures.append(
            "HomeView must subscribe to ApplicationMutationStreaming instead of task(id:) or onAppear reloads"
        )
    if "mutationStream: homeDependencies.mutationStream" not in home_view_source:
        failures.append(
            "HomeView must observe the feature mutation stream for automatic invalidation"
        )

if mutation_repository_path.exists():
    mutation_repository_source = mutation_repository_path.read_text()
    function_pattern = re.compile(r"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)[^{]*\{")
    for function_match in function_pattern.finditer(mutation_repository_source):
        body_start = function_match.end() - 1
        depth = 0
        body_end = None
        for index in range(body_start, len(mutation_repository_source)):
            character = mutation_repository_source[index]
            if character == "{":
                depth += 1
            elif character == "}":
                depth -= 1
                if depth == 0:
                    body_end = index
                    break
        if body_end is None:
            continue
        body = mutation_repository_source[body_start + 1:body_end]
        is_guarded_mutation = (
            "validateCanWrite" in body or "writePolicy.canWrite" in body
        )
        if not is_guarded_mutation:
            continue
        record_index = body.find("mutationRecorder.recordSuccessfulMutation")
        last_base_call_index = body.rfind("base.")
        if record_index == -1:
            line = mutation_repository_source.count("\n", 0, function_match.start()) + 1
            failures.append(
                f"{mutation_repository_path}:{line}: {function_match.group(1)} must publish a successful application mutation"
            )
        elif record_index < last_base_call_index:
            line = mutation_repository_source.count("\n", 0, function_match.start()) + 1
            failures.append(
                f"{mutation_repository_path}:{line}: {function_match.group(1)} publishes before persistence succeeds"
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
