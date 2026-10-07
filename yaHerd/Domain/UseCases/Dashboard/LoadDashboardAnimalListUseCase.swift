import Foundation

@MainActor
struct LoadDashboardAnimalListUseCase {
    let repository: any DashboardQueryReading
    let deriver: any DashboardHomeDeriving

    init(
        repository: any DashboardQueryReading,
        deriver: any DashboardHomeDeriving = DashboardHomeDerivationActor()
    ) {
        self.repository = repository
        self.deriver = deriver
    }

    func execute(
        kind: DashboardAnimalListKind,
        configuration: DashboardConfiguration
    ) async throws -> [DashboardAnimalItem] {
        let animals = try await repository.fetchDashboardAnimalRecords(kind: kind)
        let records = DashboardRecords(animals: animals, pastures: [], workingSessions: [])
        return await deriver.makeDashboardAnimalList(
            kind: kind,
            records: records,
            configuration: configuration,
            now: .now
        )
    }
}
