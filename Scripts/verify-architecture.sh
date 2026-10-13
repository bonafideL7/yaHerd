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

# Swift imports may carry attributes such as @_spi(Internal), access-level
# modifiers such as 'private' and 'package' (Swift 6), or both. Extract the
# imported module once for the Domain and persistence boundaries; typed imports
# (for example, private import struct CloudKit.CKDatabase) use that same module.
swift_import = re.compile(
    r"^\s*(?:@[_A-Za-z]\w*(?:\s*\([^()\r\n]*\))?\s+|"
    r"(?:private|fileprivate|internal|package|public|open)\s+)*"
    r"import\s+(?:(?:class|struct|enum|protocol|func|var|typealias|operator|precedencegroup|macro)\s+)?"
    r"(?P<module>[_A-Za-z]\w*)\b"
)

for path in root.rglob("*.swift"):
    source = path.read_text()
    for line_number, line in enumerate(source.splitlines(), start=1):
        match = swift_import.match(line)
        if match and match.group("module") not in allowed_imports:
            failures.append(
                f'{path}:{line_number}: Domain imports platform framework {match.group("module")}'
            )

    for match in re.finditer(r"\b(?:CK[A-Z][A-Za-z0-9_]*|NSManagedObject|ModelContext|SwiftUI\.View|UIViewController)\b", source):
        line_number = source.count("\n", 0, match.start()) + 1
        failures.append(
            f"{path}:{line_number}: Domain references platform type {match.group(0)}"
        )


# Milestone 11: preserve the closed original SwiftData schema outside the app
# source tree until a data-preserving existing-user upgrade decision is made.
# A full frozen-file manifest and content pins prevent silent archive expansion.
legacy_swiftdata_blobs = {
    Path("LegacySwiftData/Data/Models/Animal/Animal.swift"): "464336aa1650225d1a9f624fb56f01e0a9df7fa2",
    Path("LegacySwiftData/Data/Models/Animal/AnimalStatusReference.swift"): "1818c4aaa41a5e7c545b895d6dda92de2cdb4930",
    Path("LegacySwiftData/Data/Models/Animal/AnimalTag.swift"): "815c31554c01905b7bf880762482b8f04192100d",
    Path("LegacySwiftData/Data/Models/Animal/StatusRecord.swift"): "109a55bd457e639f79b9a601e9e38daf92ce5ed6",
    Path("LegacySwiftData/Data/Models/Check/FieldCheckSession.swift"): "3099f739eace70ce487e40a3c80c1be8a5dfa9ba",
    Path("LegacySwiftData/Data/Models/Health/HealthRecord.swift"): "c0bddf52ed48cb76227247420dd8a754cb05403c",
    Path("LegacySwiftData/Data/Models/Health/PregnancyCheck.swift"): "5737840d022a22885db205cd5241bf4ad140938c",
    Path("LegacySwiftData/Data/Models/Herd/Herd.swift"): "819957a63e7fd8504bc5759d640727196f5b93f6",
    Path("LegacySwiftData/Data/Models/Pasture/MovementRecord.swift"): "79c7b07bcdbe359a0a2c0fbfe2fe805f23d039b1",
    Path("LegacySwiftData/Data/Models/Pasture/Pasture.swift"): "468c89a7f28a527bb2b31edcc88cd56c38d71790",
    Path("LegacySwiftData/Data/Models/Pasture/PastureGroup.swift"): "a1b2c451282f48f8f507c247d8a0941784ee8d1b",
    Path("LegacySwiftData/Data/Models/Support/TagColorDefinition.swift"): "2791218a0a433d665ed7219e04b6120c94b84d74",
    Path("LegacySwiftData/Data/Models/Work/WorkingProtocolTemplate.swift"): "5126021f43bc1b0ec4d241c954581bfa5eb5961f",
    Path("LegacySwiftData/Data/Models/Work/WorkingQueueItem.swift"): "d3eb4f2f670fd1ca785222b84e7ff46623b1333e",
    Path("LegacySwiftData/Data/Models/Work/WorkingSession.swift"): "48f899d0c2d7866c93e3861760f00e34aed8fd1b",
    Path("LegacySwiftData/Data/Models/Work/WorkingTreatmentRecord.swift"): "76be1fd0e98e51e5a113abd34bd676126db0bdb7",
    Path("LegacySwiftData/Data/Models/Work/WorkingTreatmentTerminologyCompatibility.swift"): "c2baee50fcaecad4828218b7b5c46814e7ede766",
    Path("LegacySwiftData/Data/Persistence/Schema/YaHerdCurrentModels.swift"): "8b8d7db05a9ac03cafe86288da39f94d2241ca47",
    Path("LegacySwiftData/Data/Persistence/Schema/YaHerdSchemaV1.swift"): "4a50d3965c16cfdef0eff2418f49902ccae17863",
}
# The archive is deliberately outside all Xcode source roots. Pin its closed
# membership as well as its content so adding an unreviewed SwiftData model
# cannot silently expand the historical schema inventory.
archive_root = Path("LegacySwiftData")
archived_sources = set(archive_root.rglob("*.swift")) if archive_root.is_dir() else set()
unexpected_archived_sources = archived_sources - set(legacy_swiftdata_blobs)
if unexpected_archived_sources:
    failures.append(
        "LegacySwiftData: unexpected source(s) outside the frozen schema manifest: "
        + ", ".join(str(path) for path in sorted(unexpected_archived_sources))
    )

# Preserve exact Git blob identities for historical model, schema and alias
# sources. Any future schema archive change requires an explicit review.
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

# The archived SwiftData files are no longer inside the synchronized yaHerd
# source root. All attached app-target exceptions together must exclude only
# Info.plist; another set cannot silently exclude active Core Data/Domain code.
project_path = Path("yaHerd.xcodeproj/project.pbxproj")
project_text = project_path.read_text()
# The frozen archive must never be compiled by either application or test.
# It lives outside both synchronized source roots and must not be manually
# reattached through a file/group reference or another source root.
if "LegacySwiftData" in project_text:
    failures.append("yaHerd.xcodeproj: frozen SwiftData archive must not be an Xcode target source")
app_exception_id = "8D2190483009470D00DE8E34"
app_target_id = "8D40A2892EDAA29E00C89DD2"
app_root_group_id = "8D40A28C2EDAA29E00C89DD2"
expected_app_exclusions = {"Info.plist"}

def pbx_object_body(identifier: str) -> str | None:
    found = re.search(
        rf"(?ms)^\s*{identifier}\b[^\n]*=\s*\{{(?P<body>.*?)^\s*\}};",
        project_text,
    )
    return found.group("body") if found else None

# A synchronized source root may attach more than one target-specific
# exception set. Validate the aggregate that Xcode will apply, not just
# the original set: an additional app-target set could otherwise silently
# remove a live Domain/Core Data source from compilation.
app_group_body = pbx_object_body(app_root_group_id)
app_target_body = pbx_object_body(app_target_id)
attached_exception_ids: list[str] = []

if app_group_body is None or (
    "isa = PBXFileSystemSynchronizedRootGroup;" not in app_group_body
):
    failures.append("yaHerd.xcodeproj: missing synchronized app source root")
else:
    attached = re.search(r"\bexceptions\s*=\s*\((.*?)\);", app_group_body, re.S)
    if attached is None:
        failures.append("yaHerd.xcodeproj: app source root has no exception list")
    else:
        # Remove descriptive PBX comments before reading reference IDs.
        references = re.sub(r"/\*.*?\*/", "", attached.group(1), flags=re.S)
        reference_entries = references.split(",")
        if reference_entries[-1].strip() == "":
            reference_entries.pop()
        for entry in reference_entries:
            reference = entry.strip()
            if not re.fullmatch(r"[0-9A-F]{24}", reference):
                failures.append(
                    f"yaHerd.xcodeproj: malformed app source exception reference {reference!r}"
                )
            else:
                attached_exception_ids.append(reference)

if app_exception_id not in attached_exception_ids:
    failures.append("yaHerd.xcodeproj: original app-source exception set is detached")
if len(attached_exception_ids) != len(set(attached_exception_ids)):
    failures.append("yaHerd.xcodeproj: duplicate attached source exception-set reference")

if app_target_body is None:
    failures.append("yaHerd.xcodeproj: app target is missing")
else:
    roots = re.search(
        r"\bfileSystemSynchronizedGroups\s*=\s*\((.*?)\);",
        app_target_body,
        re.S,
    )
    if roots is None or app_root_group_id not in roots.group(1):
        failures.append("yaHerd.xcodeproj: app target no longer includes its source root")

app_exclusions: list[str] = []
app_exception_set_count = 0
for exception_id in attached_exception_ids:
    exception_body = pbx_object_body(exception_id)
    if exception_body is None:
        failures.append(
            f"yaHerd.xcodeproj: referenced source exception set {exception_id} is missing"
        )
        continue
    if "isa = PBXFileSystemSynchronizedBuildFileExceptionSet;" not in exception_body:
        failures.append(
            f"yaHerd.xcodeproj: attached source exception {exception_id} has wrong object type"
        )
        continue
    target = re.search(r"\btarget\s*=\s*([0-9A-F]{24})\b", exception_body)
    if target is None:
        failures.append(
            f"yaHerd.xcodeproj: attached source exception {exception_id} has no target"
        )
        continue
    if target.group(1) != app_target_id:
        continue  # An attached exception for a different target cannot omit app sources.
    app_exception_set_count += 1
    membership = re.search(r"\bmembershipExceptions\s*=\s*\((.*?)\);", exception_body, re.S)
    if membership is None:
        failures.append(
            f"yaHerd.xcodeproj: app source exception {exception_id} has no membership paths"
        )
        continue
    for entry in membership.group(1).splitlines():
        entry = entry.strip()
        if not entry:
            continue
        parsed = re.fullmatch(r'(?:"([^"]+)"|([A-Za-z0-9_./-]+)),', entry)
        if parsed is None:
            failures.append(
                f"yaHerd.xcodeproj: unrecognized app exclusion entry {entry!r}"
            )
            continue
        app_exclusions.append(parsed.group(1) or parsed.group(2))

if app_exception_set_count == 0:
    failures.append("yaHerd.xcodeproj: no source exception set targets the app")
missing = expected_app_exclusions - set(app_exclusions)
extra = set(app_exclusions) - expected_app_exclusions
if missing or extra or len(app_exclusions) != len(expected_app_exclusions):
    failures.append(
        "yaHerd.xcodeproj: aggregate app target exclusions must equal the "
        "Info.plist only (missing: "
        + ", ".join(sorted(missing))
        + "; unexpected: "
        + ", ".join(sorted(extra))
        + "; duplicates: "
        + str(len(app_exclusions) != len(set(app_exclusions)))
        + ")"
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
        imported = swift_import.match(code)
        module = imported.group("module") if imported else None
        if module == "SwiftData":
            failures.append(
                f"{path}:{line_number}: SwiftData import is forbidden in production code"
            )
        declaration = swiftdata_declaration.search(code)
        if declaration:
            failures.append(
                f"{path}:{line_number}: SwiftData macro is forbidden in production code"
            )
        for runtime_api in swiftdata_runtime_api.finditer(code):
            failures.append(
                f"{path}:{line_number}: SwiftData runtime API {runtime_api.group(0)} is forbidden"
            )
        if legacy_schema_reference.search(code):
            failures.append(
                f"{path}:{line_number}: active production code must not reference the retired SwiftData schema"
            )
        if module == "CloudKit" or cloudkit_api.search(code):
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