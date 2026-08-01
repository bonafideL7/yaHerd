import Foundation

@MainActor
struct LoadDashboardPastureListUseCase {
    let repository: any DashboardQueryReading
    let service: DashboardService

    init(repository: any DashboardQueryReading, service: DashboardService = DashboardService()) {
        self.repository = repository
        self.service = service
    }

    func execute(configuration: DashboardConfiguration) async throws -> [DashboardPastureItem] {
        let pastures = try await repository.fetchDashboardPastureRecords()
        let records = DashboardRecords(animals: [], pastures: pastures, workingSessions: [])
        return service.makeSnapshot(records: records, configuration: configuration).pastures
    }
}
