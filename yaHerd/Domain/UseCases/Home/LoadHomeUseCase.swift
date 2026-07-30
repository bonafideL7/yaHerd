import Foundation

@MainActor
struct LoadHomeUseCase {
    let dashboardReadModel: any DashboardReadModel
    let fieldCheckReadModel: any HomeFieldCheckReadModel
    let workingReadModel: any HomeWorkingReadModel
    let snapshotBuilder: HomeSnapshotBuilderActor

    init(
        dashboardReadModel: any DashboardReadModel,
        fieldCheckReadModel: any HomeFieldCheckReadModel,
        workingReadModel: any HomeWorkingReadModel,
        snapshotBuilder: HomeSnapshotBuilderActor = HomeSnapshotBuilderActor()
    ) {
        self.dashboardReadModel = dashboardReadModel
        self.fieldCheckReadModel = fieldCheckReadModel
        self.workingReadModel = workingReadModel
        self.snapshotBuilder = snapshotBuilder
    }

    func execute(
        configuration: DashboardConfiguration,
        now: Date = .now
    ) async throws -> HomeSnapshot {
        try await PerformanceLog.measureAsync("LoadHomeUseCase.execute") {
            async let dashboardRecords = dashboardReadModel.fetchDashboardRecords(pageSize: 250)
            async let fieldCheckSessions = fieldCheckReadModel.fetchRecentSessions(limit: 250)
            async let openFindings = fieldCheckReadModel.fetchOpenFindings(limit: 100)
            async let treatmentTemplates = workingReadModel.fetchTreatmentTemplates(limit: 100)

            let records = try await (
                dashboardRecords,
                fieldCheckSessions,
                openFindings,
                treatmentTemplates
            )

            return await snapshotBuilder.makeSnapshot(
                dashboardRecords: records.0,
                fieldCheckSessions: records.1,
                openFindings: records.2,
                treatmentTemplates: records.3,
                configuration: configuration,
                now: now
            )
        }
    }
}
