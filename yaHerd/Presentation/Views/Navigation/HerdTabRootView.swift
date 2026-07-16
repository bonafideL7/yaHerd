import SwiftUI

struct HerdTabRootView: View {
    @Environment(AppNavigationState.self) private var navigation
    @FocusState private var searchFieldIsFocused: Bool

    private var router: HerdRouter { navigation.herdRouter }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            HerdView(
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
                onOpenAnimal: { navigation.openAnimal($0) },
                onOpenPasture: { navigation.openPasture($0) },
                onOpenFieldChecks: { router.openFieldChecks(.all) },
                onOpenWorkSessions: { router.openWorkingSessions() },
                onOpenSettings: { navigation.present(.settings) }
            )
            .navigationDestination(for: HerdRoute.self) { route in
                destination(route)
            }
        }
        .searchable(
            text: $router.searchText,
            prompt: "Search tag, color, or name"
        )
        .searchFocused($searchFieldIsFocused)
        .simultaneousGesture(searchFocusDismissGesture)
        .task {
            searchFieldIsFocused = router.isSearchPresented
        }
        .onChange(of: router.isSearchPresented) { _, isPresented in
            searchFieldIsFocused = isPresented
        }
        .onChange(of: searchFieldIsFocused) { _, isFocused in
            router.isSearchPresented = isFocused || !router.searchText.isEmpty
        }
    }

    private var searchPresentationBinding: Binding<Bool> {
        Binding {
            router.isSearchPresented || !router.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } set: { isPresented in
            if isPresented {
                router.presentSearch(query: router.searchText)
            } else {
                router.dismissSearch(clearText: true)
            }
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
                guard searchFieldIsFocused else { return }

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
