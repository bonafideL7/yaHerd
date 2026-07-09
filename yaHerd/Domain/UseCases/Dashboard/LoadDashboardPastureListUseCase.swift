import Foundation

struct LoadDashboardPastureListUseCase {
    let repository: any DashboardRecordReading
    let service: DashboardService

    init(repository: any DashboardRecordReading, service: DashboardService = DashboardService()) {
        self.repository = repository
        self.service = service
    }

    func execute(configuration: DashboardConfiguration) throws -> [DashboardPastureItem] {
        let pastures = try repository.fetchDashboardPastureRecords()
        let records = DashboardRecords(animals: [], pastures: pastures, workingSessions: [])
        return service.makeSnapshot(records: records, configuration: configuration).pastures
    }
}
