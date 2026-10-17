# Animal list sorting control — behavior matrix

## Diagnosis and design

**Observed by user:** Tapping **Sort** does nothing; the previous fix (PR #191's first two commits) only corrected sort options and never fixed menu presentation.

**Affected production caller graph:**
- `MainTabView` attaches `HerdTabBottomAccessory` via `.tabViewBottomAccessory`. This view chooses between `AnimalListTabAccessoryControls` and `AnimalListInlineTabAccessoryControls` as iOS 26 expands/collapses the tab bar.
- Both variants currently put `AnimalSortMenuPicker` inside `Menu`. A working Picker binding does not help when the menu itself is not presented.
- A separate fallback `AnimalListFloatingControlBar` also wraps the Picker inside `Menu`.
- The existing state owner is `AppNavigationState.herdRouter.sortOrder` for YaHerd and Search, and `AnimalListView.sortOrderBinding` for standalone lists. The actual list recomputation is triggered by `AnimalListView.onChange(of: sortOrderValue)` and calculated in `AnimalListViewModel` / `AnimalListDerivationActor`.

**Fix approach:** Use tappable **Button** controls instead of nested accessory `Menu` → `Picker`:
1. Main tab accessory Sort button dispatches to `MainTabView`, which owns and presents a native sort confirmation dialog **outside** the tab-bar accessory hierarchy. Each action writes the exact `HerdRouter.sortOrder` enum case. Use one dialog for both inline and expanded accessory layouts.
2. Standalone animal-list floating Sort button opens its own confirmation dialog and writes the existing `sortOrder` Binding. This fallback is not used by the shell tabs.
3. Keep eight distinct sort choices and truthful current-selection labels; preserve existing top-bar reverse button, state restoration, search/filter, list derivation and grouped sections.
4. Do not change list repositories, Core Data or business sorting comparators. Runtime symptom is a missing menu presentation, not evidence that the comparator fails.

## Coverage matrix

| Production operation / behavior | Production callers | Success path | Error / rollback path | Clear / reset behavior | Batch / mixed-input behavior | Same-context behavior | Fresh-context reload | Production read projections | Relationships / history | Cross-feature effects | Unrelated control records | Identity / metadata | Contract owner |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Main-tab sort interaction and presentation | MainTabView → HerdTabBottomAccessory → AnimalListAdaptiveTabAccessoryControls → AnimalListTabAccessoryControls / AnimalListInlineTabAccessoryControls | Covered: normal Button invokes parent callback and parent-owned confirmation dialog for all eight choices, outside native accessory placement | Covered: Cancel/dismiss leaves the prior sort value unchanged; no data write | Covered: after selecting any option user can reopen the dialog; no stale nested Picker or separate menu-selection state | N/A: sort changes list display, not batch data writes | Covered: Button callback changes MainTabView presentation state; dialog actions change shared HerdRouter.sortOrder | Covered: existing router sortOrder is persisted in HerdRouterSnapshot | Covered: AnimalListView observes sortOrderValue and asynchronously recalculates filteredAndSortedAnimals and groupedAnimals | N/A: no persistent relationship/history mutation | Covered: same shell accessory shared by YaHerd and Search, and by inline/expanded native accessory placements | Covered: no change to pasture list or other tab accessories | Covered: exact enum sort value survives navigation/restoration and retains direction | This PR |
| Standalone floating-bar sort interaction | AnimalListView → AnimalListFloatingControlBar | Covered: Button opens floating control's sort confirmation dialog and writes the supplied Binding using exact cases | Covered: dismissing dialog does not mutate the current sort | Covered: can choose a new value immediately after closing; full eight options remain available | N/A: no batch mutation | Covered: inherited sortOrder Binding routes back to AnimalListView.refreshDerivedState | N/A: standalone view retains its existing sort-owner lifecycle | Covered: same cached derivation actor and comparator as shell view | N/A: no data relationships changed | Covered: fallback works without any dependency on MainTabView state | Covered: does not interfere with the list's filter/search and inline edit controls | Covered: no new UUIDs/record identities or sort normalization | This PR |
| Sort direction and section behavior preserved | AnimalListToolbarContent.reverseSortDirection → AnimalListView; AnimalListDerivations.filteredAndSortedAnimals / groupedAnimals | Covered: Tag A→Z, Tag Z→A, Birth newest/oldest, Sex, Animal Type, Status, Pasture remain distinct; top-bar arrow still reverses only Tag/Birth | N/A: read-only derivation and existing error state unchanged | Covered: restoring/clearing filters does not reset chosen sort; Cancel never changes value | Covered: batch mode and collapsed grouped sections keep existing behavior | Covered: sort change triggers onChange and nondebounced derived-state scheduling | Covered: existing router snapshot Codable sortOrder unaffected | Covered: derivation receives unchanged enum and still uses existing sorting/grouping comparators | N/A: no Core Data writes | Covered: YaHerd and Search still use shared router-owned sort by current design | Covered: no effects on unrelated animals or pasture records | Covered: enum raw values, sort metadata and ID ordering contract unchanged | This PR |

## Verification and ownership

- This PR owns the **Sort tap → dialog presentation → exact selected enum** behavior in both accessory placements and fallback floating control.
- The existing AnimalListViewModel/AnimalListDerivations implementation owns row-order correctness and asynchronous generation safety; it is not modified by this PR. The sort remains a read-only projection with no write or persistence API change.
- Source-level review of caller graph, all control variants and bindings, then full diff review.
- Manual iOS checks required: tap Sort in YaHerd; tap Sort when tab bar is collapsed; tap Sort in Search; tap Sort in standalone floating bar; confirm dialog opens each time. Choose Tag A→Z/Z→A, Birth Newest/Oldest, all grouped choices, and Cancel. Verify displayed selection matches rows and top-bar reverse state.
- **Not executed:** build, tests, lint or CI. `AGENTS.md` prohibits execution absent explicit user request.
