import Foundation

struct LoadDashboardAnimalListUseCase {
    let repository: any DashboardRecordReading
    let service: DashboardService

    init(repository: any DashboardRecordReading, service: DashboardService = DashboardService()) {
        self.repository = repository
        self.service = service
    }

    func execute(
        kind: DashboardAnimalListKind,
        configuration: DashboardConfiguration
    ) throws -> [DashboardAnimalItem] {
        let animals = try repository.fetchDashboardAnimalRecords(kind: kind)
        let records = DashboardRecords(animals: animals, pastures: [], workingSessions: [])
        return service.makeAnimalList(kind: kind, records: records, configuration: configuration)
    }
}
