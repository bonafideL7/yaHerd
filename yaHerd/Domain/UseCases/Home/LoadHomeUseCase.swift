import Foundation

@MainActor
struct LoadHomeUseCase {
    let dashboardRepository: any DashboardQueryReading
    let fieldCheckRepository: any HomeFieldCheckQueryReading
    let workingRepository: any HomeWorkingQueryReading
    let service: HomeService

    init(
        dashboardRepository: any DashboardQueryReading,
        fieldCheckRepository: any HomeFieldCheckQueryReading,
        workingRepository: any HomeWorkingQueryReading,
        service: HomeService = HomeService()
    ) {
        self.dashboardRepository = dashboardRepository
        self.fieldCheckRepository = fieldCheckRepository
        self.workingRepository = workingRepository
        self.service = service
    }

    func execute(
        configuration: DashboardConfiguration,
        now: Date = .now
    ) async throws -> HomeSnapshot {
        try await PerformanceLog.measureAsync("Home.load") {
            async let dashboardRecords = dashboardRepository.fetchDashboardRecords()
            async let fieldCheckRecords = fieldCheckRepository.fetchHomeFieldCheckRecords()
            async let treatmentTemplates = workingRepository.fetchHomeTreatmentTemplates(limit: 250)

            let dashboard = try await dashboardRecords
            let fieldChecks = try await fieldCheckRecords
            let templates = try await treatmentTemplates

            return service.makeSnapshot(
                dashboardRecords: dashboard,
                fieldCheckSessions: fieldChecks.sessions,
                openFindings: fieldChecks.openFindings,
                treatmentTemplates: templates,
                openFindingCount: fieldChecks.openFindingCount,
                hasFieldCheckHistory: fieldChecks.hasHistory,
                configuration: configuration,
                now: now
            )
        }
    }
}
