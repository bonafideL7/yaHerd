import Foundation

struct LoadDashboardPastureListUseCase {
    let repository: any DashboardRepository
    let service: DashboardService

    init(repository: any DashboardRepository, service: DashboardService = DashboardService()) {
        self.repository = repository
        self.service = service
    }

    func execute(configuration: DashboardConfiguration) throws -> [DashboardPastureItem] {
        let records = try repository.fetchDashboardRecords()
        let snapshot = service.makeSnapshot(records: records, configuration: configuration)
        return snapshot.pastures
    }
}
