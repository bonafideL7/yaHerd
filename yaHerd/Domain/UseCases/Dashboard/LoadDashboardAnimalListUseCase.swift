import Foundation

@MainActor
struct LoadDashboardAnimalListUseCase {
    let repository: any DashboardQueryReading
    let service: DashboardService

    init(repository: any DashboardQueryReading, service: DashboardService = DashboardService()) {
        self.repository = repository
        self.service = service
    }

    func execute(
        kind: DashboardAnimalListKind,
        configuration: DashboardConfiguration
    ) async throws -> [DashboardAnimalItem] {
        let animals = try await repository.fetchDashboardAnimalRecords(kind: kind)
        let records = DashboardRecords(animals: animals, pastures: [], workingSessions: [])
        return service.makeAnimalList(kind: kind, records: records, configuration: configuration)
    }
}
