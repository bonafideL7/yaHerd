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
    @EnvironmentObject private var dependencies: AppDependencies
    @AppStorage("isDashboardEnabled") private var isDashboardEnabled = false
    
    @State private var selectedTab: MainTab = .home
    @State private var isShowingSettings = false
    @State private var isPresentingAddAnimal = false
    @State private var isPresentingAddPasture = false
    @State private var isPresentingNewWorkingSession = false
    @State private var isStartingFieldCheck = false
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
        if animalFilter.care.isActive { count += 1 }
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
                NavigationStack {
                    HomeView(
                        isPresentingAddAnimal: $isPresentingAddAnimal,
                        isPresentingAddPasture: $isPresentingAddPasture,
                        isPresentingNewWorkingSession: $isPresentingNewWorkingSession,
                        isStartingFieldCheck: $isStartingFieldCheck,
                        openAnimalList: openAnimalList,
                        openPastureList: openPastureList
                    )
                    .yaherdInlineLargeNavigationTitle("Home")
                    .appSettingsToolbar(isPresented: $isShowingSettings)
                }
            }
            
            if isDashboardEnabled {
                Tab("Dashboard", systemImage: "rectangle.3.group", value: MainTab.dashboard) {
                    NavigationStack(path: $nav.globalPath) {
                        DashboardView(
                            openAnimalList: openAnimalList,
                            openPastureList: openPastureList
                        )
                            .yaherdInlineLargeNavigationTitle("Dashboard")
                            .appSettingsToolbar(isPresented: $isShowingSettings)
                            .navigationDestination(for: DashboardRoute.self, destination: dashboardDestination)
                    }
                }
            }
            
            Tab(value: MainTab.animals) {
                NavigationStack {
                    herdContent
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
                    herdContent
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
        .onChange(of: isDashboardEnabled) { _, isEnabled in
            if !isEnabled && selectedTab == .dashboard {
                selectedTab = .home
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .search {
                herdMode = .animals
                DispatchQueue.main.async {
                    animalSearchFieldIsFocused = false
                }
            }
            
            if oldValue == .search && newValue != .search {
                animalSearchFieldIsFocused = false
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
    
    @ViewBuilder
    private func dashboardDestination(for route: DashboardRoute) -> some View {
        switch route {
        case .animal(let id):
            AnimalDetailView(animalID: id)
        case .pasture(let id):
            PastureDetailView(pastureID: id)
        case .animalList(let kind):
            DashboardAnimalListView(kind: kind, repository: dependencies.dashboardRepository)
        case .pastureList:
            DashboardPastureListView(repository: dependencies.dashboardRepository)
        }
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
