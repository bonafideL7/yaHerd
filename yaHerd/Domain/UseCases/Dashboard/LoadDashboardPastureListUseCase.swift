import Foundation

@MainActor
struct LoadDashboardPastureListUseCase {
    let repository: any DashboardQueryReading
    let deriver: any DashboardHomeDeriving

    init(
        repository: any DashboardQueryReading,
        deriver: any DashboardHomeDeriving = DashboardHomeDerivationActor()
    ) {
        self.repository = repository
        self.deriver = deriver
    }

    func execute(configuration: DashboardConfiguration) async throws -> [DashboardPastureItem] {
        let pastures = try await repository.fetchDashboardPastureRecords()
        let records = DashboardRecords(animals: [], pastures: pastures, workingSessions: [])
        return await deriver.makeDashboardPastureList(
            records: records,
            configuration: configuration,
            now: .now
        )
    }
}
