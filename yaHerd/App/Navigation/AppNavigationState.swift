import Foundation
import Observation

/// Top-level tabs with stable raw values for restoration and deep links.
enum AppTab: String, Codable, Hashable {
    case home
    case dashboard
    case herd
    case search
}

/// Routes owned by the herd navigation stack.
enum HerdRoute: Codable, Hashable {
    case animal(UUID)
    case pasture(UUID)
    case pastureGroups
    case fieldChecks(FieldChecksViewMode)
    case workingSessions
}

/// Routes owned by isolated field-check and working-session flows.
enum WorkflowRoute: Codable, Hashable {
    case fieldCheckSessions(FieldChecksViewMode)
    case fieldCheckSession(FieldCheckSessionLaunchConfiguration)
    case workingSessions
    case workingSession(UUID)
}

enum AppPresentedSheet: String, Codable, Identifiable, Hashable {
    case settings
    case addAnimal
    case addPasture
    case startFieldCheck
    case startWorkingSession

    var id: String { rawValue }
}

enum AppFullScreenWorkflow: String, Codable, Identifiable, Hashable {
    case fieldCheck
    case workingSession

    var id: String { rawValue }
}

/// Provider-neutral navigation input for notifications, widgets, shortcuts, and tests.
enum AppNavigationRequest: Codable, Hashable, Sendable {
    case openAnimal(UUID)
    case openPasture(UUID)
    case openFinding(sessionID: UUID, findingID: UUID)
    case continueFieldCheck(UUID)
    case continueWorkingSession(UUID)
    case searchAnimals(String)
}

struct HerdRouterSnapshot: Codable, Equatable {
    var path: [HerdRoute]
    var searchPath: [HerdRoute]?
    var mode: HerdViewMode
    var searchText: String
    var isSearchPresented: Bool
    var sortOrder: AnimalSortOrder
    var filter: AnimalFilter
    var pastureFilter: PastureListFilter
    var showRemovedStatuses: Bool
    var showArchivedRecords: Bool
}

@MainActor
@Observable
final class HerdRouter {
    private let animalQuery: AnimalQueryState

    var path: [HerdRoute] = []
    var searchPath: [HerdRoute] = []
    var mode: HerdViewMode = .animals
    var isSearchPresented = false
    var pastureFilter: PastureListFilter = .all

    init(animalQuery: AnimalQueryState = AnimalQueryState()) {
        self.animalQuery = animalQuery
    }

    var searchText: String {
        get { animalQuery.searchText }
        set { animalQuery.searchText = newValue }
    }

    var sortOrder: AnimalSortOrder {
        get { animalQuery.sortOrder }
        set { animalQuery.sortOrder = newValue }
    }

    var filter: AnimalFilter {
        get { animalQuery.filter }
        set { animalQuery.filter = newValue }
    }

    var showRemovedStatuses: Bool {
        get { animalQuery.showRemovedStatuses }
        set { animalQuery.showRemovedStatuses = newValue }
    }

    var showArchivedRecords: Bool {
        get { animalQuery.showArchivedRecords }
        set { animalQuery.showArchivedRecords = newValue }
    }

    var showingFilters: Bool {
        get { animalQuery.showingFilters }
        set { animalQuery.showingFilters = newValue }
    }

    var snapshot: HerdRouterSnapshot {
        HerdRouterSnapshot(
            path: path,
            searchPath: searchPath,
            mode: mode,
            searchText: searchText,
            isSearchPresented: isSearchPresented,
            sortOrder: sortOrder,
            filter: filter,
            pastureFilter: pastureFilter,
            showRemovedStatuses: showRemovedStatuses,
            showArchivedRecords: showArchivedRecords
        )
    }

    func restore(_ snapshot: HerdRouterSnapshot) {
        path = snapshot.path
        searchPath = snapshot.searchPath ?? []
        mode = snapshot.mode
        animalQuery.restore(
            searchText: snapshot.searchText,
            sortOrder: snapshot.sortOrder,
            filter: snapshot.filter,
            showRemovedStatuses: snapshot.showRemovedStatuses,
            showArchivedRecords: snapshot.showArchivedRecords
        )
        isSearchPresented = snapshot.isSearchPresented
        pastureFilter = snapshot.pastureFilter
    }

    func showAnimals(_ configuration: AnimalListLaunchConfiguration = .active) {
        path.removeAll()
        mode = .animals
        animalQuery.apply(configuration)
        isSearchPresented = !configuration.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func showPastures(_ configuration: PastureListLaunchConfiguration = .all) {
        path.removeAll()
        mode = .pastures
        pastureFilter = configuration.filter
    }

    func path(for tab: AppTab) -> [HerdRoute] {
        tab == .search ? searchPath : path
    }

    func setPath(_ newPath: [HerdRoute], for tab: AppTab) {
        if tab == .search {
            searchPath = newPath
        } else {
            path = newPath
        }
    }

    func openAnimal(_ animalID: UUID, in tab: AppTab = .herd) {
        mode = .animals
        setPath([.animal(animalID)], for: tab)
    }

    func openPasture(_ pastureID: UUID, in tab: AppTab = .herd) {
        mode = .pastures
        setPath([.pasture(pastureID)], for: tab)
    }

    func openFieldChecks(_ mode: FieldChecksViewMode = .all, in tab: AppTab = .herd) {
        var activePath = path(for: tab)
        activePath.append(.fieldChecks(mode))
        setPath(activePath, for: tab)
    }

    func openWorkingSessions(in tab: AppTab = .herd) {
        var activePath = path(for: tab)
        activePath.append(.workingSessions)
        setPath(activePath, for: tab)
    }

    func showSearch(query: String = "") {
        searchText = query
        isSearchPresented = true
    }

    func dismissSearch(clearText: Bool) {
        isSearchPresented = false
        if clearText {
            clearAnimalCriteria()
        }
    }

    func clearAnimalCriteria() {
        animalQuery.clearCriteria()
    }
}

struct WorkflowRouterSnapshot: Codable, Equatable {
    var route: WorkflowRoute?
}

@MainActor
@Observable
final class WorkflowRouter {
    var route: WorkflowRoute?

    var snapshot: WorkflowRouterSnapshot {
        WorkflowRouterSnapshot(route: route)
    }

    func restore(_ snapshot: WorkflowRouterSnapshot) {
        route = snapshot.route
    }

    func reset() {
        route = nil
    }
}

struct AppNavigationSnapshot: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var selectedTab: AppTab
    var herdRouter: HerdRouterSnapshot
    var workflowRouter: WorkflowRouterSnapshot
    var presentedSheet: AppPresentedSheet?
    var fullScreenWorkflow: AppFullScreenWorkflow?
}

@MainActor
@Observable
final class AppNavigationState {
    var selectedTab: AppTab = .home
    let animalQuery: AnimalQueryState
    let herdRouter: HerdRouter
    let workflowRouter = WorkflowRouter()
    var presentedSheet: AppPresentedSheet?
    var fullScreenWorkflow: AppFullScreenWorkflow?

    init() {
        let animalQuery = AnimalQueryState()
        self.animalQuery = animalQuery
        self.herdRouter = HerdRouter(animalQuery: animalQuery)
    }

    var snapshot: AppNavigationSnapshot {
        AppNavigationSnapshot(
            selectedTab: selectedTab,
            herdRouter: herdRouter.snapshot,
            workflowRouter: workflowRouter.snapshot,
            presentedSheet: presentedSheet,
            fullScreenWorkflow: fullScreenWorkflow
        )
    }

    func restore(from payload: String) {
        guard !payload.isEmpty,
              let data = Data(base64Encoded: payload),
              let snapshot = try? JSONDecoder().decode(AppNavigationSnapshot.self, from: data),
              snapshot.version == AppNavigationSnapshot.currentVersion
        else { return }

        selectedTab = snapshot.selectedTab == .search ? .herd : snapshot.selectedTab
        herdRouter.restore(snapshot.herdRouter)
        workflowRouter.restore(snapshot.workflowRouter)
        presentedSheet = snapshot.presentedSheet
        fullScreenWorkflow = snapshot.fullScreenWorkflow
    }

    func restorationPayload() -> String? {
        guard let data = try? JSONEncoder().encode(snapshot) else { return nil }
        return data.base64EncodedString()
    }

    func present(_ sheet: AppPresentedSheet) {
        presentedSheet = sheet
    }

    func dismissSheet() {
        presentedSheet = nil
    }

    func openAnimalList(_ configuration: AnimalListLaunchConfiguration) {
        selectedTab = .herd
        herdRouter.showAnimals(configuration)
    }

    func openPastureList(_ configuration: PastureListLaunchConfiguration) {
        selectedTab = .herd
        herdRouter.showPastures(configuration)
    }

    func openAnimal(_ animalID: UUID) {
        selectedTab = .herd
        herdRouter.openAnimal(animalID)
    }

    func openPasture(_ pastureID: UUID) {
        selectedTab = .herd
        herdRouter.openPasture(pastureID)
    }

    func selectSearchTab() {
        selectedTab = .herd
        herdRouter.isSearchPresented = true
    }

    func openSearch(query: String = "") {
        selectedTab = .herd
        herdRouter.showSearch(query: query)
    }

    func dismissSearch(clearCriteria: Bool) {
        herdRouter.dismissSearch(clearText: clearCriteria)
        if selectedTab == .search {
            selectedTab = .herd
        }
    }

    func openFieldChecks(_ mode: FieldChecksViewMode = .all) {
        selectedTab = .herd
        herdRouter.path = [.fieldChecks(mode)]
    }

    func openWorkingSessions() {
        selectedTab = .herd
        herdRouter.path = [.workingSessions]
    }

    func openFieldCheckArea(_ configuration: FieldCheckAreaLaunchConfiguration) {
        presentedSheet = nil
        workflowRouter.route = configuration.session.map(WorkflowRoute.fieldCheckSession)
            ?? .fieldCheckSessions(configuration.mode ?? .all)
        fullScreenWorkflow = .fieldCheck
    }

    func openWorkArea(_ configuration: WorkAreaLaunchConfiguration) {
        presentedSheet = nil
        workflowRouter.route = configuration.sessionID.map(WorkflowRoute.workingSession)
            ?? .workingSessions
        fullScreenWorkflow = .workingSession
    }

    func closeFullScreenWorkflow() {
        fullScreenWorkflow = nil
        workflowRouter.reset()
    }

    func handle(_ request: AppNavigationRequest) {
        switch request {
        case .openAnimal(let animalID):
            openAnimal(animalID)
        case .openPasture(let pastureID):
            openPasture(pastureID)
        case .openFinding(let sessionID, let findingID):
            openFieldCheckArea(
                .session(
                    FieldCheckSessionLaunchConfiguration(
                        sessionID: sessionID,
                        opensFindings: true,
                        focusedFindingID: findingID
                    )
                )
            )
        case .continueFieldCheck(let sessionID):
            openFieldCheckArea(.session(FieldCheckSessionLaunchConfiguration(sessionID: sessionID)))
        case .continueWorkingSession(let sessionID):
            openWorkArea(.session(sessionID))
        case .searchAnimals(let query):
            openSearch(query: query)
        }
    }

    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "yaherd" else { return false }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let destination = url.host?.lowercased() ?? ""
        let pathValues = url.pathComponents.filter { $0 != "/" }

        switch destination {
        case "animal":
            guard let value = pathValues.first, let id = UUID(uuidString: value) else { return false }
            handle(.openAnimal(id))
        case "pasture":
            guard let value = pathValues.first, let id = UUID(uuidString: value) else { return false }
            handle(.openPasture(id))
        case "field-check":
            guard let value = pathValues.first, let sessionID = UUID(uuidString: value) else { return false }
            if let findingValue = components?.queryItems?.first(where: { $0.name == "finding" })?.value,
               let findingID = UUID(uuidString: findingValue) {
                handle(.openFinding(sessionID: sessionID, findingID: findingID))
            } else {
                handle(.continueFieldCheck(sessionID))
            }
        case "work-session":
            guard let value = pathValues.first, let id = UUID(uuidString: value) else { return false }
            handle(.continueWorkingSession(id))
        case "search":
            let query = components?.queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            handle(.searchAnimals(query))
        default:
            return false
        }

        return true
    }
}
