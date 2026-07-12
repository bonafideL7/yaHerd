import Foundation

struct AnimalListLaunchConfiguration: Hashable {
    var searchText: String = ""
    var sortOrder: AnimalSortOrder = .tagAscending
    var filter: AnimalFilter = AnimalFilter()
    var showRemovedStatuses: Bool = false
    var showArchivedRecords: Bool = false

    static let active = AnimalListLaunchConfiguration()

    static let workingPen = AnimalListLaunchConfiguration(
        sortOrder: .pasture,
        filter: AnimalFilter(location: .workingPen)
    )

    static let missingPasture = AnimalListLaunchConfiguration(
        sortOrder: .pasture,
        filter: AnimalFilter(recordIssue: .missingPasture)
    )

    static let missingTags = AnimalListLaunchConfiguration(
        filter: AnimalFilter(recordIssue: .missingTag)
    )

    static let unknownSex = AnimalListLaunchConfiguration(
        sortOrder: .sex,
        filter: AnimalFilter(recordIssue: .unknownSex)
    )

    static let archivedActive = AnimalListLaunchConfiguration(
        filter: AnimalFilter(status: .active, recordIssue: .archivedActive),
        showArchivedRecords: true
    )

    static func dashboard(_ kind: DashboardAnimalListKind) -> AnimalListLaunchConfiguration {
        switch kind {
        case .active:
            return .active
        case .workingPen:
            return .workingPen
        case .unassigned:
            return .missingPasture
        }
    }
}

struct PastureListLaunchConfiguration: Hashable {
    var filter: PastureListFilter = .all

    static let all = PastureListLaunchConfiguration()
    static let underutilized = PastureListLaunchConfiguration(filter: .underutilized)
    static let rotationReady = PastureListLaunchConfiguration(filter: .rotationReady)
    static let missingStockingData = PastureListLaunchConfiguration(filter: .missingStockingData)

    static func dashboard(_ filter: DashboardPastureFilter) -> PastureListLaunchConfiguration {
        switch filter {
        case .all:
            return .all
        case .underutilized:
            return .underutilized
        case .rotationReady:
            return .rotationReady
        }
    }
}


struct FieldCheckSessionLaunchConfiguration: Identifiable, Hashable {
    let token: UUID
    let sessionID: UUID
    var opensFindings: Bool
    var opensFlaggedRoster: Bool
    var opensRemainingRoster: Bool
    var opensMissingRoster: Bool

    var id: UUID { token }

    init(
        sessionID: UUID,
        opensFindings: Bool = false,
        opensFlaggedRoster: Bool = false,
        opensRemainingRoster: Bool = false,
        opensMissingRoster: Bool = false,
        token: UUID = UUID()
    ) {
        self.token = token
        self.sessionID = sessionID
        self.opensFindings = opensFindings
        self.opensFlaggedRoster = opensFlaggedRoster
        self.opensRemainingRoster = opensRemainingRoster
        self.opensMissingRoster = opensMissingRoster
    }
}


struct FieldCheckAreaLaunchConfiguration: Identifiable, Hashable {
    let token: UUID
    let mode: FieldChecksViewMode?
    let session: FieldCheckSessionLaunchConfiguration?

    var id: UUID { token }

    init(
        mode: FieldChecksViewMode? = nil,
        session: FieldCheckSessionLaunchConfiguration? = nil,
        token: UUID = UUID()
    ) {
        self.token = token
        self.mode = mode
        self.session = session
    }

    static func sessions(_ mode: FieldChecksViewMode = .all) -> FieldCheckAreaLaunchConfiguration {
        FieldCheckAreaLaunchConfiguration(mode: mode)
    }

    static func session(_ configuration: FieldCheckSessionLaunchConfiguration) -> FieldCheckAreaLaunchConfiguration {
        FieldCheckAreaLaunchConfiguration(session: configuration)
    }
}

struct WorkAreaLaunchConfiguration: Identifiable, Hashable {
    let token: UUID
    let sessionID: UUID?

    var id: UUID { token }

    init(sessionID: UUID? = nil, token: UUID = UUID()) {
        self.token = token
        self.sessionID = sessionID
    }

    static var sessions: WorkAreaLaunchConfiguration {
        WorkAreaLaunchConfiguration()
    }

    static func session(_ sessionID: UUID) -> WorkAreaLaunchConfiguration {
        WorkAreaLaunchConfiguration(sessionID: sessionID)
    }
}
