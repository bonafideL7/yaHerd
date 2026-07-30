import Foundation

@MainActor
struct LoadDashboardUseCase {
    let readModel: any DashboardReadModel

    init(readModel: any DashboardReadModel) {
        self.readModel = readModel
    }

    func execute(
        configuration: DashboardConfiguration,
        now: Date = .now
    ) async throws -> DashboardSnapshot {
        try await readModel.fetchDashboardSnapshot(
            configuration: configuration,
            now: now
        )
    }
}
