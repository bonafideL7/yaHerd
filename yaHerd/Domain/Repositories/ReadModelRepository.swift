import Foundation

struct ReadPageRequest: Hashable, Sendable {
    static let defaultLimit = 250
    static let maximumLimit = 500

    let offset: Int
    let limit: Int

    init(offset: Int = 0, limit: Int = defaultLimit) {
        self.offset = max(offset, 0)
        self.limit = min(max(limit, 1), Self.maximumLimit)
    }
}

struct AnimalSummaryPage: Sendable {
    let animals: [AnimalSummary]
    let hasMore: Bool
}

enum AnimalListQueryPastureFilter: Hashable, Sendable {
    case any
    case noPasture
    case pasture(UUID)
}

enum AnimalListQueryLocationFilter: Hashable, Sendable {
    case any
    case pasture
    case workingPen
}

enum AnimalListQueryRecordIssueFilter: Hashable, Sendable {
    case any
    case missingPasture
    case missingTag
    case unknownSex
    case archivedActive
}

enum AnimalListQuerySortOrder: String, Hashable, Sendable {
    case tagAscending
    case tagDescending
    case birthDateNewest
    case birthDateOldest
    case sex
    case animalType
    case status
    case pasture
}

struct AnimalListFilterQuery: Hashable, Sendable {
    let searchText: String
    let sex: Sex?
    let animalType: AnimalType?
    let status: AnimalStatus?
    let pasture: AnimalListQueryPastureFilter
    let location: AnimalListQueryLocationFilter
    let recordIssue: AnimalListQueryRecordIssueFilter
    let showRemovedStatuses: Bool
    let showArchivedRecords: Bool
    let sortOrder: AnimalListQuerySortOrder

    init(
        searchText: String = "",
        sex: Sex? = nil,
        animalType: AnimalType? = nil,
        status: AnimalStatus? = nil,
        pasture: AnimalListQueryPastureFilter = .any,
        location: AnimalListQueryLocationFilter = .any,
        recordIssue: AnimalListQueryRecordIssueFilter = .any,
        showRemovedStatuses: Bool = false,
        showArchivedRecords: Bool = false,
        sortOrder: AnimalListQuerySortOrder = .tagAscending
    ) {
        self.searchText = searchText
        self.sex = sex
        self.animalType = animalType
        self.status = status
        self.pasture = pasture
        self.location = location
        self.recordIssue = recordIssue
        self.showRemovedStatuses = showRemovedStatuses
        self.showArchivedRecords = showArchivedRecords
        self.sortOrder = sortOrder
    }
}

struct HomeFieldCheckRecords: Sendable {
    /// Every session that can contribute an unfinished, flagged, or missing warning row.
    let sessions: [FieldCheckSessionSummary]

    /// Home only needs a finding value when exactly one unresolved finding exists.
    /// Larger result sets navigate to the complete findings destination by count.
    let openFindings: [FieldCheckFindingSnapshot]
    let openFindingCount: Int
    let hasHistory: Bool
}

protocol DashboardQueryReading: Sendable {
    func fetchDashboardRecords() async throws -> DashboardRecords
    func fetchDashboardAnimalRecords(kind: DashboardAnimalListKind) async throws -> [DashboardAnimalRecord]
    func fetchDashboardPastureRecords() async throws -> [DashboardPastureRecord]
}

protocol HomeFieldCheckQueryReading: Sendable {
    func fetchHomeFieldCheckRecords() async throws -> HomeFieldCheckRecords
}

protocol HomeWorkingQueryReading: Sendable {
    func fetchHomeTreatmentTemplates(limit: Int) async throws -> [WorkingTreatmentTemplateSummary]
}

protocol AnimalListQueryReading: Sendable {
    func fetchAnimalSummaryPage(_ request: ReadPageRequest) async throws -> AnimalSummaryPage
    func fetchAnimalPastureOptions(limit: Int) async throws -> [PastureOption]
}

protocol AnimalListFilteredQueryReading: Sendable {
    func fetchAnimalSummaryPage(
        matching query: AnimalListFilterQuery,
        page: ReadPageRequest
    ) async throws -> AnimalSummaryPage
}
