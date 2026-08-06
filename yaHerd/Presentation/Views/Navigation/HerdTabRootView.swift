import SwiftUI

struct HerdTabRootView: View {
    let tab: AppTab

    @Environment(AppNavigationState.self) private var navigation

    init(tab: AppTab = .herd) {
        self.tab = tab
    }

    private var router: HerdRouter { navigation.herdRouter }
    private var query: AnimalQueryState { navigation.animalQuery }

    var body: some View {
        @Bindable var query = query
        @Bindable var router = router

        if showsAnimalQueryControls {
            herdNavigationStack
                .searchable(
                    text: $query.searchText,
                    isPresented: $router.isSearchPresented,
                    prompt: "Search tag, visual ID, or name"
                )
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
            router.isSearchPresented
        } set: { isPresented in
            router.isSearchPresented = isPresented
        }
    }

    private var showsAnimalQueryControls: Bool {
        guard navigation.selectedTab == .herd else { return false }
        guard let destination = router.path(for: tab).last else { return true }

        if case .pasture = destination {
            return true
        }

        return false
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
}

struct HerdTabBottomAccessory: View {
    @Environment(AppNavigationState.self) private var navigation

    private var query: AnimalQueryState { navigation.animalQuery }

    var body: some View {
        @Bindable var query = query

        PersistentAnimalQueryControls(
            sortOrder: $query.sortOrder,
            filtersAreActive: query.filtersAreActive,
            activeFilterCount: query.activeFilterCount,
            hasAnyActiveCriteria: query.hasAnyActiveCriteria,
            onShowFilters: { query.showingFilters = true },
            onClearAllCriteria: { query.clearCriteria() }
        )
    }
}
