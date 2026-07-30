import Foundation

@MainActor
struct LoadHomeUseCase {
    let dashboardReadModel: any DashboardReadModel
    let fieldCheckReadModel: any HomeFieldCheckReadModel
    let workingReadModel: any HomeWorkingReadModel
    let service: HomeService

    init(
        dashboardReadModel: any DashboardReadModel,
        fieldCheckReadModel: any HomeFieldCheckReadModel,
        workingReadModel: any HomeWorkingReadModel,
        service: HomeService = HomeService()
    ) {
        self.dashboardReadModel = dashboardReadModel
        self.fieldCheckReadModel = fieldCheckReadModel
        self.workingReadModel = workingReadModel
        self.service = service
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

            return try await service.makeSnapshot(
                dashboardRecords: dashboardRecords,
                fieldCheckSessions: fieldCheckSessions,
                openFindings: openFindings,
                treatmentTemplates: treatmentTemplates,
                configuration: configuration,
                now: now
            )
        }
    }
}
