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
