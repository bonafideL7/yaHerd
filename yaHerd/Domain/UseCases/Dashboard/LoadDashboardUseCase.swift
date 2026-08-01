import Foundation

@MainActor
struct LoadDashboardUseCase {
    let repository: any DashboardQueryReading
    let service: DashboardService

    init(repository: any DashboardQueryReading, service: DashboardService = DashboardService()) {
        self.repository = repository
        self.service = service
    }

    func execute(configuration: DashboardConfiguration) async throws -> DashboardSnapshot {
        let records = try await repository.fetchDashboardRecords()
        return service.makeSnapshot(records: records, configuration: configuration)
    }
}
