import Foundation

@MainActor
struct LoadDashboardUseCase {
    let repository: any DashboardQueryReading
    let deriver: any DashboardHomeDeriving

    init(
        repository: any DashboardQueryReading,
        deriver: any DashboardHomeDeriving = DashboardHomeDerivationActor()
    ) {
        self.repository = repository
        self.deriver = deriver
    }

    func execute(configuration: DashboardConfiguration) async throws -> DashboardSnapshot {
        let records = try await repository.fetchDashboardRecords()
        return await deriver.makeDashboardSnapshot(
            records: records,
            configuration: configuration,
            now: .now
        )
    }
}
