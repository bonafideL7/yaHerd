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
