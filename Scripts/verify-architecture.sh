#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PYTHON'
from pathlib import Path
import plistlib
import re
import sys
import hashlib

root = Path("yaHerd/Domain")
allowed_imports = {"Foundation"}
failures: list[str] = []

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


# Milestone 11: freeze (do not expand) the dormant SwiftData schema until an
# explicit data-preserving upgrade decision permits its complete retirement.
# Exact files, not a directory wildcard: new model files cannot opt themselves
# into the temporary exception simply by residing alongside the old schema.
legacy_swiftdata_blobs = {
    Path("yaHerd/Data/Models/Animal/Animal.swift"): "464336aa1650225d1a9f624fb56f01e0a9df7fa2",
    Path("yaHerd/Data/Models/Animal/AnimalStatusReference.swift"): "1818c4aaa41a5e7c545b895d6dda92de2cdb4930",
    Path("yaHerd/Data/Models/Animal/AnimalTag.swift"): "815c31554c01905b7bf880762482b8f04192100d",
    Path("yaHerd/Data/Models/Animal/StatusRecord.swift"): "109a55bd457e639f79b9a601e9e38daf92ce5ed6",
    Path("yaHerd/Data/Models/Check/FieldCheckSession.swift"): "3099f739eace70ce487e40a3c80c1be8a5dfa9ba",
    Path("yaHerd/Data/Models/Health/HealthRecord.swift"): "c0bddf52ed48cb76227247420dd8a754cb05403c",
    Path("yaHerd/Data/Models/Health/PregnancyCheck.swift"): "5737840d022a22885db205cd5241bf4ad140938c",
    Path("yaHerd/Data/Models/Herd/Herd.swift"): "819957a63e7fd8504bc5759d640727196f5b93f6",
    Path("yaHerd/Data/Models/Pasture/MovementRecord.swift"): "79c7b07bcdbe359a0a2c0fbfe2fe805f23d039b1",
    Path("yaHerd/Data/Models/Pasture/Pasture.swift"): "468c89a7f28a527bb2b31edcc88cd56c38d71790",
    Path("yaHerd/Data/Models/Pasture/PastureGroup.swift"): "a1b2c451282f48f8f507c247d8a0941784ee8d1b",
    Path("yaHerd/Data/Models/Support/TagColorDefinition.swift"): "2791218a0a433d665ed7219e04b6120c94b84d74",
    Path("yaHerd/Data/Models/Work/WorkingProtocolTemplate.swift"): "5126021f43bc1b0ec4d241c954581bfa5eb5961f",
    Path("yaHerd/Data/Models/Work/WorkingQueueItem.swift"): "d3eb4f2f670fd1ca785222b84e7ff46623b1333e",
    Path("yaHerd/Data/Models/Work/WorkingSession.swift"): "48f899d0c2d7866c93e3861760f00e34aed8fd1b",
    Path("yaHerd/Data/Models/Work/WorkingTreatmentRecord.swift"): "76be1fd0e98e51e5a113abd34bd676126db0bdb7",
    Path("yaHerd/Data/Models/Work/WorkingTreatmentTerminologyCompatibility.swift"): "c2baee50fcaecad4828218b7b5c46814e7ede766",
    Path("yaHerd/Data/Persistence/Schema/YaHerdCurrentModels.swift"): "8b8d7db05a9ac03cafe86288da39f94d2241ca47",
    Path("yaHerd/Data/Persistence/Schema/YaHerdSchemaV1.swift"): "4a50d3965c16cfdef0eff2418f49902ccae17863",
}
legacy_models_root = Path("yaHerd/Data/Models")
legacy_model_sources = {
    path for path in legacy_swiftdata_blobs if path.is_relative_to(legacy_models_root)
}
legacy_schema_source = Path("yaHerd/Data/Persistence/Schema/YaHerdSchemaV1.swift")
legacy_swiftdata_sources = legacy_model_sources | {legacy_schema_source}
legacy_schema_reference_sources = legacy_swiftdata_sources | {
    Path("yaHerd/Data/Persistence/Schema/YaHerdCurrentModels.swift"),
}

# The file-path allowlist alone would permit new @Model declarations, relationships
# or a container inside an existing file. Pin all archived schema-related sources,
# including the alias files, to their existing Git blob IDs. An intentional future
# change must explicitly update this inventory in code review.
for path, expected_blob in legacy_swiftdata_blobs.items():
    if not path.is_file():
        failures.append(f"{path}: archived SwiftData declaration source is missing")
        continue
    contents = path.read_bytes()
    git_blob = hashlib.sha1(
        b"blob " + str(len(contents)).encode("ascii") + b"\0" + contents
    ).hexdigest()
    if git_blob != expected_blob:
        failures.append(
            f"{path}: archived SwiftData declarations changed; "
            "review preservation of the legacy schema before updating its pinned blob"
        )

swiftdata_import = re.compile(
    r"^\s*(?:@preconcurrency\s+)?import\s+(?:(?:class|struct|enum|protocol|func|var|typealias)\s+)?SwiftData\b"
)
cloudkit_import = re.compile(
    r"^\s*(?:@preconcurrency\s+)?import\s+(?:(?:class|struct|enum|protocol|func|var|typealias)\s+)?CloudKit\b"
)
swiftdata_declaration = re.compile(r"^\s*@(Model|Query|ModelActor)\b")
swiftdata_runtime_api = re.compile(
    r"\b(?:ModelContext|ModelContainer|ModelConfiguration|SchemaMigrationPlan|VersionedSchema)\b"
)
cloudkit_api = re.compile(r"\b(?:NSPersistentCloudKitContainer|CKContainer)\b")
legacy_schema_reference = re.compile(r"\bYaHerdSchemaV1\b")

for path in Path("yaHerd").rglob("*.swift"):
    # The check covers every production source folder, not only Data/CoreData.
    # Ignore // comment-only lines so descriptions of deprecated APIs are safe.
    for line_number, line in enumerate(path.read_text().splitlines(), start=1):
        code = line.split("//", 1)[0]
        if not code.strip():
            continue
        if swiftdata_import.search(code) and path not in legacy_swiftdata_sources:
            failures.append(
                f"{path}:{line_number}: SwiftData import is forbidden outside frozen legacy model/schema files"
            )
        declaration = swiftdata_declaration.search(code)
        if declaration and not (
            declaration.group(1) == "Model" and path in legacy_model_sources
        ):
            failures.append(
                f"{path}:{line_number}: SwiftData macro is forbidden outside the existing archived @Model declarations"
            )
        for runtime_api in swiftdata_runtime_api.finditer(code):
            if runtime_api.group(0) == "VersionedSchema" and path == legacy_schema_source:
                continue
            failures.append(
                f"{path}:{line_number}: SwiftData runtime API {runtime_api.group(0)} is forbidden"
            )
        if legacy_schema_reference.search(code) and path not in legacy_schema_reference_sources:
            failures.append(
                f"{path}:{line_number}: active production code must not reference the retired SwiftData schema"
            )
        if cloudkit_import.search(code) or cloudkit_api.search(code):
            failures.append(
                f"{path}:{line_number}: CloudKit/shared persistence is not part of the local-only architecture"
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
    "dashboardRecordReader", "herdRepository",
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
}
missing_feature_dependency_keys = required_feature_dependency_keys - feature_dependency_keys
if missing_feature_dependency_keys:
    failures.append(
        "Missing feature dependency environment values: "
        + ", ".join(sorted(missing_feature_dependency_keys))
    )

settings_catalog_path = Path("yaHerd/App/Preferences/ApplicationSettingCatalog.swift")
known_setting_literals = {
    "isDashboardEnabled",
    "hardDeleteAnimals",
    "targetAcresPerHeadDefault",
    "usableAcreagePercentDefault",
    "recentPastureIDs",
    "recentPastureNames",
    "homeDismissedSetupSuggestionIDs",
    "homeSetupSuggestionsExpanded",
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

    if not re.search(r"enum\s+AppTab\b[\s\S]*?\bcase\s+search\b", navigation_source):
        failures.append("AppTab must retain the permanent Search tab")

main_tab_source = main_tab_path.read_text()
if len(main_tab_source.splitlines()) > 120:
    failures.append(
        "MainTabView.swift exceeds 120 lines; move navigation behavior into routers or feature roots"
    )
if "@State" in main_tab_source or "NavigationPath" in main_tab_source:
    failures.append(
        "MainTabView must not own navigation paths or modal/search workflow state"
    )
required_search_tab_fragments = (
    "value: AppTab.search",
    "role: .search",
    "HerdTabRootView(tab: .search)",
)
for required_fragment in required_search_tab_fragments:
    if required_fragment not in main_tab_source:
        failures.append(
            f"Search must remain available in the tab menu and reuse the herd hierarchy: missing {required_fragment}"
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