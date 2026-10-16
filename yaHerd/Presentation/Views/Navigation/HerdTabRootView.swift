import SwiftUI

struct HerdTabRootView: View {
    let tab: AppTab

    @Environment(AppNavigationState.self) private var navigation
    @FocusState private var searchFieldIsFocused: Bool

    init(tab: AppTab = .herd) {
        self.tab = tab
    }

    private var router: HerdRouter { navigation.herdRouter }

    var body: some View {
        @Bindable var router = router

        if tab == .search {
            herdNavigationStack
                .searchable(
                    text: $router.searchText,
                    prompt: "Search tag, color, or name"
                )
                .searchFocused($searchFieldIsFocused)
                .simultaneousGesture(searchFocusDismissGesture)
                .task {
                    prepareSearchTabIfSelected()
                }
                .onChange(of: navigation.selectedTab) { oldValue, newValue in
                    handleTabSelectionChange(from: oldValue, to: newValue)
                }
        } else {
            herdNavigationStack
        }
    }

    private var herdNavigationStack: some View {
        NavigationStack(path: navigationPathBinding) {
            herdContent
                .navigationDestination(for: HerdRoute.self) { route in
                    destination(route)
                }
        }
    }

    private var herdContent: some View {
        @Bindable var router = router

        return HerdView(
            searchText: $router.searchText,
            isSearchPresented: searchPresentationBinding,
            mode: $router.mode,
            sortOrder: $router.sortOrder,
            filter: $router.filter,
            showRemovedStatuses: $router.showRemovedStatuses,
            showArchivedRecords: $router.showArchivedRecords,
            showingFilters: $router.showingFilters,
            pastureFilter: $router.pastureFilter,
            usesShellBottomAccessory: true,
            onOpenAnimal: { router.openAnimal($0, in: tab) },
            onOpenPasture: { router.openPasture($0, in: tab) },
            onOpenFieldChecks: { router.openFieldChecks(.all, in: tab) },
            onOpenWorkSessions: { router.openWorkingSessions(in: tab) },
            onOpenSettings: { navigation.present(.settings) }
        )
    }

    private var navigationPathBinding: Binding<[HerdRoute]> {
        Binding {
            router.path(for: tab)
        } set: { newPath in
            router.setPath(newPath, for: tab)
        }
    }

    private var searchPresentationBinding: Binding<Bool> {
        Binding {
            navigation.selectedTab == .search || hasSearchText
        } set: { isPresented in
            if isPresented {
                navigation.selectSearchTab()
            } else {
                navigation.dismissSearch(clearCriteria: true)
            }
        }
    }

    private var hasSearchText: Bool {
        !router.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func prepareSearchTabIfSelected() {
        guard navigation.selectedTab == .search else { return }
        router.mode = .animals
        router.isSearchPresented = true

        Task { @MainActor in
            await Task.yield()
            searchFieldIsFocused = false
        }
    }

    private func handleTabSelectionChange(from oldValue: AppTab, to newValue: AppTab) {
        if newValue == .search {
            router.mode = .animals
            router.isSearchPresented = true

            Task { @MainActor in
                await Task.yield()
                searchFieldIsFocused = false
            }
        }

        if oldValue == .search && newValue != .search {
            searchFieldIsFocused = false
            router.isSearchPresented = hasSearchText
        }
    }

    @ViewBuilder
    private func destination(_ route: HerdRoute) -> some View {
        switch route {
        case .animal(let animalID):
            AnimalDetailView(animalID: animalID)
        case .pasture(let pastureID):
            PastureDetailView(pastureID: pastureID)
        case .fieldChecks(let mode):
            FieldChecksView(mode: mode, onSessionLaunch: { configuration in
                navigation.openFieldCheckArea(.session(configuration))
            })
        case .workingSessions:
            WorkingSessionsView { sessionID in
                navigation.openWorkArea(.session(sessionID))
            }
        }
    }

    private var searchFocusDismissGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard navigation.selectedTab == .search, searchFieldIsFocused else { return }

                let verticalDrag = value.translation.height
                let horizontalDrag = abs(value.translation.width)
                if verticalDrag > 28 && verticalDrag > horizontalDrag {
                    searchFieldIsFocused = false
                }
            }
    }
}

struct HerdTabBottomAccessory: View {
    @Environment(AppNavigationState.self) private var navigation

    private var router: HerdRouter { navigation.herdRouter }

    var body: some View {
        @Bindable var router = router

        AnimalListAdaptiveTabAccessoryControls(
            sortOrder: $router.sortOrder,
            filtersAreActive: filtersAreActive,
            activeFilterCount: activeFilterCount,
            hasAnyActiveCriteria: hasAnyActiveCriteria,
            onShowFilters: { router.showingFilters = true },
            onClearAllCriteria: { router.clearAnimalCriteria() }
        )
    }

    private var hasSearchText: Bool {
        !router.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filtersAreActive: Bool {
        router.filter.isActive || router.showRemovedStatuses || router.showArchivedRecords
    }

    private var hasAnyActiveCriteria: Bool {
        hasSearchText || filtersAreActive
    }

    private var activeFilterCount: Int {
        var count = 0
        if router.showRemovedStatuses { count += 1 }
        if router.showArchivedRecords { count += 1 }
        if router.filter.sex != nil { count += 1 }
        if router.filter.animalType != nil { count += 1 }
        if router.filter.status != nil { count += 1 }

        switch router.filter.pasture {
        case .any:
            break
        case .noPasture, .pasture:
            count += 1
        }

        if router.filter.location.isActive { count += 1 }
        if router.filter.recordIssue.isActive { count += 1 }
        return count
    }
}
