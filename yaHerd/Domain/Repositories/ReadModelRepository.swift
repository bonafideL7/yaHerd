import Foundation

struct AnimalListSnapshot: Sendable {
    let animals: [AnimalSummary]
    let pastureOptions: [PastureOption]
}

protocol DashboardReadModel: Sendable {
    func fetchDashboardRecords(pageSize: Int) async throws -> DashboardRecords
    func fetchDashboardSnapshot(
        configuration: DashboardConfiguration,
        now: Date,
        pageSize: Int
    ) async throws -> DashboardSnapshot
}

extension DashboardReadModel {
    func fetchDashboardRecords() async throws -> DashboardRecords {
        try await fetchDashboardRecords(pageSize: 250)
    }

    func fetchDashboardSnapshot(
        configuration: DashboardConfiguration,
        now: Date = .now
    ) async throws -> DashboardSnapshot {
        try await fetchDashboardSnapshot(
            configuration: configuration,
            now: now,
            pageSize: 250
        )
    }
}

protocol HomeFieldCheckReadModel: Sendable {
    func fetchRecentSessions(limit: Int) async throws -> [FieldCheckSessionSummary]
    func fetchOpenFindings(limit: Int) async throws -> [FieldCheckFindingSnapshot]
}

protocol HomeWorkingReadModel: Sendable {
    func fetchTreatmentTemplates(limit: Int) async throws -> [WorkingTreatmentTemplateSummary]
}

protocol AnimalListReadModel: Sendable {
    func fetchAnimalListSnapshot(pageSize: Int) async throws -> AnimalListSnapshot
}

extension AnimalListReadModel {
    func fetchAnimalListSnapshot() async throws -> AnimalListSnapshot {
        try await fetchAnimalListSnapshot(pageSize: 250)
    }
}

@MainActor
protocol AnimalListReadModelProviding {
    var animalListReadModel: any AnimalListReadModel { get }
}
