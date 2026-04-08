import Foundation

struct LoadDashboardUseCase {
    let repository: any DashboardRepository
    let service: DashboardService

    init(repository: any DashboardRepository, service: DashboardService = DashboardService()) {
        self.repository = repository
        self.service = service
    }

    func execute(configuration: DashboardConfiguration) throws -> DashboardSnapshot {
        let records = try repository.fetchDashboardRecords()
        return service.makeSnapshot(records: records, configuration: configuration)
    }
}
