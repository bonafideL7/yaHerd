import SwiftUI

struct HerdTabRootView: View {
    let tab: AppTab

    @Environment(AppNavigationState.self) private var navigation
    @FocusState private var searchFieldIsFocused: Bool

    init(tab: AppTab = .herd) {
        self.tab = tab
    }

    private var router: HerdRouter { navigation.herdRouter }
    private var query: AnimalQueryState { navigation.animalQuery }

    var body: some View {
        @Bindable var query = query

        if tab == .search {
            herdNavigationStack
                .searchable(
                    text: $query.searchText,
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
        @Bindable var query = query

        return HerdView(
            searchText: $query.searchText,
            isSearchPresented: searchPresentationBinding,
            mode: $router.mode,
            sortOrder: $query.sortOrder,
            filter: $query.filter,
            showRemovedStatuses: $query.showRemovedStatuses,
            showArchivedRecords: $query.showArchivedRecords,
            showingFilters: $query.showingFilters,
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
            navigation.selectedTab == .search || query.hasSearchText
        } set: { isPresented in
            if isPresented {
                navigation.selectSearchTab()
            } else {
                navigation.dismissSearch(clearCriteria: true)
            }
        }
    }

    private func prepareSearchTabIfSelected() {
        guard navigation.selectedTab == .search else { return }
        router.isSearchPresented = true

        Task { @MainActor in
            await Task.yield()
            searchFieldIsFocused = false
        }
    }

    private func handleTabSelectionChange(from oldValue: AppTab, to newValue: AppTab) {
        if newValue == .search {
            router.isSearchPresented = true

            Task { @MainActor in
                await Task.yield()
                searchFieldIsFocused = false
            }
        }

        if oldValue == .search && newValue != .search {
            searchFieldIsFocused = false
            router.isSearchPresented = query.hasSearchText
        }
    }

    @ViewBuilder
    private func destination(_ route: HerdRoute) -> some View {
        switch route {
        case .animal(let animalID):
            AnimalDetailView(animalID: animalID)
        case .pasture(let pastureID):
            PastureDetailView(pastureID: pastureID)
        case .pastureGroups:
            PastureGroupListView()
        case .fieldCheckSetup(let pastureID):
            FieldCheckSessionSetupView(suggestedPastureID: pastureID) { sessionID in
                navigation.openFieldCheckArea(
                    .session(FieldCheckSessionLaunchConfiguration(sessionID: sessionID))
                )
            }
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

    private var query: AnimalQueryState { navigation.animalQuery }

    var body: some View {
        @Bindable var query = query

        AnimalListAdaptiveTabAccessoryControls(
            sortOrder: $query.sortOrder,
            filtersAreActive: query.filtersAreActive,
            activeFilterCount: query.activeFilterCount,
            hasAnyActiveCriteria: query.hasAnyActiveCriteria,
            onShowFilters: { query.showingFilters = true },
            onClearAllCriteria: { query.clearCriteria() }
        )
    }
}
