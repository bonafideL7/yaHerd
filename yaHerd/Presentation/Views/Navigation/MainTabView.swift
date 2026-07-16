import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum MainTab: Hashable {
    case home
    case dashboard
    case animals
    case search
}

struct MainTabView: View {
    @EnvironmentObject private var nav: NavigationCoordinator
    @Environment(\.collaborationDependencies) private var collaborationDependencies
    private var herdSharingSyncCoordinator: HerdSharingSyncCoordinator? { collaborationDependencies.syncCoordinator }
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(ApplicationSettings.self) private var applicationSettings
    
    @State private var selectedTab: MainTab = .home
    @State private var homePath = NavigationPath()
    @State private var isShowingSettings = false
    @State private var isPresentingAddAnimal = false
    @State private var isPresentingAddPasture = false
    @State private var isPresentingNewWorkingSession = false
    @State private var isStartingFieldCheck = false
    @State private var homeRefreshToken = 0
    @State private var isolatedFieldCheckRoute: FieldCheckAreaLaunchConfiguration?
    @State private var isolatedWorkRoute: WorkAreaLaunchConfiguration?
    @State private var stackedFieldCheckRoute: FieldCheckAreaLaunchConfiguration?
    @State private var stackedWorkRoute: WorkAreaLaunchConfiguration?
    @State private var animalSearchText = ""
    @State private var herdMode: HerdViewMode = .animals
    @State private var animalSortOrder: AnimalSortOrder = .tagAscending
    @State private var animalFilter = AnimalFilter()
    @State private var pastureFilter = PastureListFilter.all
    @State private var animalShowRemovedStatuses = false
    @State private var animalShowArchivedRecords = false
    @State private var animalShowingFilters = false
    @FocusState private var animalSearchFieldIsFocused: Bool
    
    private var animalSearchIsActive: Binding<Bool> {
        Binding {
            selectedTab == .search || hasAnimalSearchText
        } set: { newValue in
            if newValue {
                selectedTab = .search
            } else {
                dismissAnimalSearch(clearText: true)
            }
        }
    }
    
    private var hasAnimalSearchText: Bool {
        !animalSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var animalFiltersAreActive: Bool {
        animalFilter.isActive || animalShowRemovedStatuses || animalShowArchivedRecords
    }
    
    private var animalHasAnyActiveCriteria: Bool {
        hasAnimalSearchText || animalFiltersAreActive
    }
    
    private var activeAnimalCriteriaCount: Int {
        var count = hasAnimalSearchText ? 1 : 0
        
        if animalShowRemovedStatuses { count += 1 }
        if animalShowArchivedRecords { count += 1 }
        if animalFilter.sex != nil { count += 1 }
        if animalFilter.animalType != nil { count += 1 }
        if animalFilter.status != nil { count += 1 }
        
        switch animalFilter.pasture {
        case .any:
            break
        case .noPasture, .pasture(_):
            count += 1
        }

        if animalFilter.location.isActive { count += 1 }
        if animalFilter.recordIssue.isActive { count += 1 }
        
        return count
    }
    
    private var activeAnimalFilterCount: Int {
        activeAnimalCriteriaCount - (hasAnimalSearchText ? 1 : 0)
    }
    
    private var shouldShowAnimalBottomAccessory: Bool {
        herdMode == .animals && (selectedTab == .animals || selectedTab == .search)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: MainTab.home) {
                NavigationStack(path: $homePath) {
                    HomeView(
                        isPresentingAddAnimal: $isPresentingAddAnimal,
                        isPresentingAddPasture: $isPresentingAddPasture,
                        isPresentingNewWorkingSession: $isPresentingNewWorkingSession,
                        isStartingFieldCheck: $isStartingFieldCheck,
                        refreshToken: homeRefreshToken,
                        openAnimalList: openAnimalList,
                        openPastureList: openPastureList,
                        openFieldCheckArea: openFieldCheckArea,
                        openWorkArea: openWorkArea
                    )
                    .yaherdInlineLargeNavigationTitle("Home")
                    .appSettingsToolbar(isPresented: $isShowingSettings)
                }
            }
            
            if applicationSettings.isDashboardEnabled {
                Tab("Dashboard", systemImage: "rectangle.3.group", value: MainTab.dashboard) {
                    NavigationStack {
                        DashboardView()
                            .yaherdInlineLargeNavigationTitle("Dashboard")
                            .appSettingsToolbar(isPresented: $isShowingSettings)
                    }
                }
            }
            
            Tab(value: MainTab.animals) {
                NavigationStack {
                    herdNavigationContent
                }
            } label: {
                Label {
                    Text("YaHerd")
                } icon: {
                    yaherdTabIcon
                }
            }
            
            Tab("Search", systemImage: "magnifyingglass", value: MainTab.search, role: .search) {
                NavigationStack {
                    herdNavigationContent
                }
                .searchable(
                    text: $animalSearchText,
                    prompt: "Search tag, color, or name"
                )
                .searchFocused($animalSearchFieldIsFocused)
                .simultaneousGesture(searchFocusDismissGesture)
            }
        }
        .yaherdTabBarMinimizeBehavior()
        .yaherdTabViewBottomAccessory(isVisible: shouldShowAnimalBottomAccessory) {
            animalBottomAccessory
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheetView()
        }
        .fullScreenCover(item: $isolatedFieldCheckRoute, onDismiss: refreshHomeData) { route in
            IsolatedFieldCheckAreaView(route: route) {
                isolatedFieldCheckRoute = nil
            }
        }
        .fullScreenCover(item: $isolatedWorkRoute, onDismiss: refreshHomeData) { route in
            IsolatedWorkAreaView(route: route) {
                isolatedWorkRoute = nil
            }
        }
        .task {
            refreshSharingAccessForActiveSurface()
        }
        .onChange(of: applicationSettings.isDashboardEnabled) { _, isEnabled in
            if !isEnabled && selectedTab == .dashboard {
                selectedTab = .home
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            refreshSharingAccessForActiveSurface(tab: newValue)

            if newValue == .home {
                refreshHomeData()
            }

            if newValue == .search {
                herdMode = .animals
                Task { @MainActor in
                    await Task.yield()
                    animalSearchFieldIsFocused = false
                }
            }
            
            if oldValue == .search && newValue != .search {
                animalSearchFieldIsFocused = false
            }
        }
        .onChange(of: herdMode) { _, newMode in
            refreshSharingAccessForActiveSurface(mode: newMode)
        }
    }
    
    private var herdNavigationContent: some View {
        herdContent
            .navigationDestination(item: $stackedFieldCheckRoute) { route in
                FieldChecksView(mode: route.mode ?? .all, onSessionLaunch: { configuration in
                    openFieldCheckArea(.session(configuration))
                })
            }
            .navigationDestination(item: $stackedWorkRoute) { route in
                WorkingSessionsView { sessionID in
                    openWorkArea(.session(sessionID))
                }
            }
    }

    private var herdContent: some View {
        HerdView(
            searchText: $animalSearchText,
            isSearchPresented: animalSearchIsActive,
            mode: $herdMode,
            sortOrder: $animalSortOrder,
            filter: $animalFilter,
            showRemovedStatuses: $animalShowRemovedStatuses,
            showArchivedRecords: $animalShowArchivedRecords,
            showingFilters: $animalShowingFilters,
            pastureFilter: $pastureFilter,
            usesShellBottomAccessory: true,
            onOpenFieldChecks: { stackedFieldCheckRoute = .sessions(.all) },
            onOpenWorkSessions: { stackedWorkRoute = .sessions },
            onOpenSettings: { isShowingSettings = true }
        )
    }
    
    @ViewBuilder
    private var yaherdTabIcon: some View {
#if canImport(UIKit)
        if let base = UIImage(named: "Cow") {
            let icon = base.scaled(to: CGSize(width: 32, height: 32))
            Image(uiImage: icon)
                .renderingMode(.template)
        } else {
            Image(systemName: "tag")
        }
#else
        Image(systemName: "tag")
#endif
    }
    
    private var animalBottomAccessory: some View {
        AnimalListAdaptiveTabAccessoryControls(
            sortOrder: $animalSortOrder,
            filtersAreActive: animalFiltersAreActive,
            activeFilterCount: activeAnimalFilterCount,
            hasAnyActiveCriteria: animalHasAnyActiveCriteria,
            onShowFilters: { animalShowingFilters = true },
            onClearAllCriteria: clearAnimalCriteria
        )
    }
    
    private var searchFocusDismissGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard selectedTab == .search, animalSearchFieldIsFocused else { return }
                
                let verticalDrag = value.translation.height
                let horizontalDrag = abs(value.translation.width)
                
                if verticalDrag > 28 && verticalDrag > horizontalDrag {
                    animalSearchFieldIsFocused = false
                }
            }
    }
    
    private func refreshSharingAccessForActiveSurface(
        tab: MainTab? = nil,
        mode: HerdViewMode? = nil
    ) {
        guard dataAccessMode.allowsDataMutations,
            let herdSharingSyncCoordinator
        else { return }

        let activeTab = tab ?? selectedTab
        let activeMode = mode ?? herdMode
        let surfaceName: String
        switch activeTab {
        case .home:
            surfaceName = "Home"
        case .dashboard:
            surfaceName = "Dashboard"
        case .animals, .search:
            switch activeMode {
            case .animals:
                surfaceName = "Animal records"
            case .pastures:
                surfaceName = "Pasture records"
            }
        }

        Task { @MainActor in
            await herdSharingSyncCoordinator.refreshSharingAccessNow(
                trigger: .screenOpened(surfaceName)
            )
        }
    }

    private func dismissAnimalSearch(clearText: Bool) {
        if clearText {
            clearAnimalCriteria()
        }
        
        if selectedTab == .search {
            selectedTab = .animals
        }
    }
    
    private func clearAnimalCriteria() {
        animalSearchText = ""
        animalFilter = AnimalFilter()
        animalShowRemovedStatuses = false
        animalShowArchivedRecords = false
    }

    private func refreshHomeData() {
        homeRefreshToken += 1
    }

    private func openFieldCheckArea(_ configuration: FieldCheckAreaLaunchConfiguration) {
        homePath = NavigationPath()
        selectedTab = .home
        isolatedFieldCheckRoute = configuration
    }

    private func openWorkArea(_ configuration: WorkAreaLaunchConfiguration) {
        homePath = NavigationPath()
        selectedTab = .home
        isolatedWorkRoute = configuration
    }

    private func openAnimalList(_ configuration: AnimalListLaunchConfiguration) {
        nav.reset()
        selectedTab = .animals
        herdMode = .animals
        animalSearchText = configuration.searchText
        animalSortOrder = configuration.sortOrder
        animalFilter = configuration.filter
        animalShowRemovedStatuses = configuration.showRemovedStatuses
        animalShowArchivedRecords = configuration.showArchivedRecords
        animalShowingFilters = false
    }

    private func openPastureList(_ configuration: PastureListLaunchConfiguration) {
        nav.reset()
        selectedTab = .animals
        herdMode = .pastures
        pastureFilter = configuration.filter
    }
    
}

private struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        ToolbarDoneButton {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private extension View {
    func appSettingsToolbar(isPresented: Binding<Bool>) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isPresented.wrappedValue = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                } label: {
                    toolbarMenuLabel
                }
                .accessibilityLabel("More actions")
            }
        }
    }
    
    private var toolbarMenuLabel: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
    }
    
    func yaherdInlineLargeNavigationTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
    }
    
    func yaherdTabBarMinimizeBehavior() -> some View {
        self.tabBarMinimizeBehavior(.onScrollDown)
    }
    
    @ViewBuilder
    func yaherdTabViewBottomAccessory<Accessory: View>(
        isVisible: Bool,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        if isVisible {
            self.tabViewBottomAccessory {
                accessory()
            }
        } else {
            self
        }
    }
}
