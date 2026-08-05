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
    var path: [HerdRoute] = []
    var searchPath: [HerdRoute] = []
    var mode: HerdViewMode = .animals
    var searchText = ""
    var isSearchPresented = false
    var sortOrder: AnimalSortOrder = .tagAscending
    var filter = AnimalFilter()
    var pastureFilter: PastureListFilter = .all
    var showRemovedStatuses = false
    var showArchivedRecords = false
    var showingFilters = false

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
        searchText = snapshot.searchText
        isSearchPresented = snapshot.isSearchPresented
        sortOrder = snapshot.sortOrder
        filter = snapshot.filter
        pastureFilter = snapshot.pastureFilter
        showRemovedStatuses = snapshot.showRemovedStatuses
        showArchivedRecords = snapshot.showArchivedRecords
        showingFilters = false
    }

    func showAnimals(_ configuration: AnimalListLaunchConfiguration = .active) {
        path.removeAll()
        mode = .animals
        searchText = configuration.searchText
        sortOrder = configuration.sortOrder
        filter = configuration.filter
        showRemovedStatuses = configuration.showRemovedStatuses
        showArchivedRecords = configuration.showArchivedRecords
        isSearchPresented = !configuration.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        showingFilters = false
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
        searchPath.removeAll()
        mode = .animals
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
        searchText = ""
        filter = AnimalFilter()
        showRemovedStatuses = false
        showArchivedRecords = false
    }
}

@MainActor
@Observable
final class WorkflowRouter {
    var route: WorkflowRoute?

    func reset() {
        route = nil
    }
}

/// Only persisted workflows backed by an existing, active repository record are restorable.
enum AppRestorableWorkflow: Codable, Equatable {
    case fieldCheckSession(UUID)
    case workingSession(UUID)
}

struct AppNavigationSnapshot: Codable, Equatable {
    static let currentVersion = 2
    static let supportedVersions = 1...currentVersion

    var version: Int = currentVersion
    var selectedTab: AppTab
    var selectedHerdID: UUID?
    var herdRouter: HerdRouterSnapshot
    var activeWorkflow: AppRestorableWorkflow?

    private enum CodingKeys: String, CodingKey {
        case version
        case selectedTab
        case selectedHerdID
        case herdRouter
        case activeWorkflow
        case workflowRouter
        case fullScreenWorkflow
    }

    init(
        version: Int = currentVersion,
        selectedTab: AppTab,
        selectedHerdID: UUID?,
        herdRouter: HerdRouterSnapshot,
        activeWorkflow: AppRestorableWorkflow?
    ) {
        self.version = version
        self.selectedTab = selectedTab
        self.selectedHerdID = selectedHerdID
        self.herdRouter = herdRouter
        self.activeWorkflow = activeWorkflow
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(selectedTab, forKey: .selectedTab)
        try container.encodeIfPresent(selectedHerdID, forKey: .selectedHerdID)
        try container.encode(herdRouter, forKey: .herdRouter)
        try container.encodeIfPresent(activeWorkflow, forKey: .activeWorkflow)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        selectedTab = try container.decode(AppTab.self, forKey: .selectedTab)
        selectedHerdID = try container.decodeIfPresent(UUID.self, forKey: .selectedHerdID)
        herdRouter = try container.decode(HerdRouterSnapshot.self, forKey: .herdRouter)

        if let workflow = try container.decodeIfPresent(AppRestorableWorkflow.self, forKey: .activeWorkflow) {
            activeWorkflow = workflow
        } else if let legacyRouter = try container.decodeIfPresent(
            LegacyWorkflowRouterSnapshot.self,
            forKey: .workflowRouter
        ) {
            let legacyPresentation = try container.decodeIfPresent(
                AppFullScreenWorkflow.self,
                forKey: .fullScreenWorkflow
            )
            activeWorkflow = Self.restorableWorkflow(
                from: legacyRouter.route,
                presentation: legacyPresentation
            )
        } else {
            activeWorkflow = nil
        }
    }

    private static func restorableWorkflow(
        from route: WorkflowRoute?,
        presentation: AppFullScreenWorkflow?
    ) -> AppRestorableWorkflow? {
        switch (presentation, route) {
        case (.fieldCheck, .fieldCheckSession(let configuration)):
            return .fieldCheckSession(configuration.sessionID)
        case (.workingSession, .workingSession(let sessionID)):
            return .workingSession(sessionID)
        default:
            return nil
        }
    }
}

private struct LegacyWorkflowRouterSnapshot: Codable {
    var route: WorkflowRoute?
}

@MainActor
protocol AppNavigationRestorationValidating {
    func currentHerdID() throws -> UUID?
    func animalExists(id: UUID) throws -> Bool
    func pastureExists(id: UUID) throws -> Bool
    func isActiveFieldCheckSession(id: UUID) throws -> Bool
    func isActiveWorkingSession(id: UUID) throws -> Bool
}

@MainActor
struct RepositoryAppNavigationRestorationValidator: AppNavigationRestorationValidating {
    let herdRepository: any HerdRepository
    let animalRepository: any AnimalDetailReading
    let pastureRepository: any PastureDetailReader
    let fieldCheckRepository: any FieldCheckSessionDetailReading
    let workingRepository: any WorkingSessionDetailReader

    func currentHerdID() throws -> UUID? {
        try herdRepository.fetchCurrentHerd().id
    }

    func animalExists(id: UUID) throws -> Bool {
        try animalRepository.fetchAnimalDetail(id: id) != nil
    }

    func pastureExists(id: UUID) throws -> Bool {
        try pastureRepository.fetchPastureDetail(id: id) != nil
    }

    func isActiveFieldCheckSession(id: UUID) throws -> Bool {
        guard let session = try fieldCheckRepository.fetchSessionDetail(id: id) else { return false }
        return !session.isCompleted
    }

    func isActiveWorkingSession(id: UUID) throws -> Bool {
        try workingRepository.fetchSessionDetail(id: id)?.status == .active
    }
}

@MainActor
@Observable
final class AppNavigationState {
    var selectedTab: AppTab = .home
    var selectedHerdID: UUID?
    let herdRouter = HerdRouter()
    let workflowRouter = WorkflowRouter()
    var presentedSheet: AppPresentedSheet?
    var fullScreenWorkflow: AppFullScreenWorkflow?

    var snapshot: AppNavigationSnapshot {
        AppNavigationSnapshot(
            selectedTab: selectedTab,
            selectedHerdID: selectedHerdID,
            herdRouter: herdRouter.snapshot,
            activeWorkflow: restorableWorkflow
        )
    }

    func restore(from payload: String) {
        restoreDurableStateWithoutRepositoryTargets(from: payload)
    }

    func restore(
        from payload: String,
        using validator: any AppNavigationRestorationValidating
    ) {
        resetTransientPresentations()
        selectedHerdID = try? validator.currentHerdID()

        guard let snapshot = decodeSnapshot(from: payload) else { return }

        selectedTab = snapshot.selectedTab
        herdRouter.restore(snapshot.herdRouter)

        let targetsCurrentHerd = snapshot.selectedHerdID == nil
            || snapshot.selectedHerdID == selectedHerdID
        guard targetsCurrentHerd else {
            herdRouter.path.removeAll()
            herdRouter.searchPath.removeAll()
            return
        }

        herdRouter.path = validatedPath(snapshot.herdRouter.path, using: validator)
        herdRouter.searchPath = validatedPath(snapshot.herdRouter.searchPath ?? [], using: validator)
        restoreActiveWorkflow(snapshot.activeWorkflow, using: validator)
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
        selectedTab = .search
        herdRouter.mode = .animals
        herdRouter.isSearchPresented = true
    }

    func openSearch(query: String = "") {
        selectedTab = .search
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

    private var restorableWorkflow: AppRestorableWorkflow? {
        switch (fullScreenWorkflow, workflowRouter.route) {
        case (.fieldCheck, .fieldCheckSession(let configuration)):
            return .fieldCheckSession(configuration.sessionID)
        case (.workingSession, .workingSession(let sessionID)):
            return .workingSession(sessionID)
        default:
            return nil
        }
    }

    private func decodeSnapshot(from payload: String) -> AppNavigationSnapshot? {
        guard !payload.isEmpty,
              let data = Data(base64Encoded: payload),
              let snapshot = try? JSONDecoder().decode(AppNavigationSnapshot.self, from: data),
              AppNavigationSnapshot.supportedVersions.contains(snapshot.version)
        else { return nil }
        return snapshot
    }

    private func resetTransientPresentations() {
        presentedSheet = nil
        fullScreenWorkflow = nil
        workflowRouter.reset()
    }

    private func restoreDurableStateWithoutRepositoryTargets(from payload: String) {
        resetTransientPresentations()
        guard let snapshot = decodeSnapshot(from: payload) else { return }

        selectedTab = snapshot.selectedTab
        herdRouter.restore(snapshot.herdRouter)
        herdRouter.path = snapshot.herdRouter.path.filter(\.isStableListRoute)
        herdRouter.searchPath = (snapshot.herdRouter.searchPath ?? []).filter(\.isStableListRoute)
    }

    private func validatedPath(
        _ path: [HerdRoute],
        using validator: any AppNavigationRestorationValidating
    ) -> [HerdRoute] {
        var validatedRoutes: [HerdRoute] = []

        for route in path {
            let isValid: Bool
            switch route {
            case .animal(let animalID):
                isValid = (try? validator.animalExists(id: animalID)) == true
            case .pasture(let pastureID):
                isValid = (try? validator.pastureExists(id: pastureID)) == true
            case .fieldChecks, .workingSessions:
                isValid = true
            }

            guard isValid else { break }
            validatedRoutes.append(route)
        }

        return validatedRoutes
    }

    private func restoreActiveWorkflow(
        _ workflow: AppRestorableWorkflow?,
        using validator: any AppNavigationRestorationValidating
    ) {
        switch workflow {
        case .fieldCheckSession(let sessionID):
            guard (try? validator.isActiveFieldCheckSession(id: sessionID)) == true else {
                openFieldChecks()
                return
            }
            workflowRouter.route = .fieldCheckSession(
                FieldCheckSessionLaunchConfiguration(sessionID: sessionID)
            )
            fullScreenWorkflow = .fieldCheck

        case .workingSession(let sessionID):
            guard (try? validator.isActiveWorkingSession(id: sessionID)) == true else {
                openWorkingSessions()
                return
            }
            workflowRouter.route = .workingSession(sessionID)
            fullScreenWorkflow = .workingSession

        case .none:
            break
        }
    }
}

private extension HerdRoute {
    var isStableListRoute: Bool {
        switch self {
        case .fieldChecks, .workingSessions:
            return true
        case .animal, .pasture:
            return false
        }
    }
}
