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

    static let missingTagNumber = AnimalListLaunchConfiguration(
        filter: AnimalFilter(recordIssue: .missingTagNumber)
    )

    static let missingTagColor = AnimalListLaunchConfiguration(
        filter: AnimalFilter(recordIssue: .missingTagColor)
    )

    static let unknownSex = AnimalListLaunchConfiguration(
        sortOrder: .sex,
        filter: AnimalFilter(recordIssue: .unknownSex)
    )

    static let archivedActive = AnimalListLaunchConfiguration(
        filter: AnimalFilter(status: .active, recordIssue: .archivedActive),
        showArchivedRecords: true
    )

    static let overduePregnancyChecks = AnimalListLaunchConfiguration(
        filter: AnimalFilter(care: .overduePregnancyCheck)
    )

    static let overdueTreatments = AnimalListLaunchConfiguration(
        filter: AnimalFilter(care: .overdueTreatment)
    )

    static let calvingWatch = AnimalListLaunchConfiguration(
        filter: AnimalFilter(care: .calvingWatch)
    )

    static func dashboard(_ kind: DashboardAnimalListKind) -> AnimalListLaunchConfiguration {
        switch kind {
        case .active:
            return .active
        case .workingPen:
            return .workingPen
        case .unassigned:
            return .missingPasture
        case .overduePregChecks:
            return .overduePregnancyChecks
        case .overdueTreatments:
            return .overdueTreatments
        case .calvingWatch:
            return .calvingWatch
        }
    }
}

struct PastureListLaunchConfiguration: Hashable {
    var filter: PastureListFilter = .all

    static let all = PastureListLaunchConfiguration()
    static let overstocked = PastureListLaunchConfiguration(filter: .overstocked)
    static let underutilized = PastureListLaunchConfiguration(filter: .underutilized)
    static let rotationReady = PastureListLaunchConfiguration(filter: .rotationReady)
    static let missingStockingData = PastureListLaunchConfiguration(filter: .missingStockingData)

    static func dashboard(_ filter: DashboardPastureFilter) -> PastureListLaunchConfiguration {
        switch filter {
        case .all:
            return .all
        case .overstocked:
            return .overstocked
        case .underutilized:
            return .underutilized
        case .rotationReady:
            return .rotationReady
        }
    }
}
