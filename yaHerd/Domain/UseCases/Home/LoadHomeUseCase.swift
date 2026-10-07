import Foundation

@MainActor
struct LoadHomeUseCase {
    let dashboardRepository: any DashboardQueryReading
    let fieldCheckRepository: any HomeFieldCheckQueryReading
    let workingRepository: any HomeWorkingQueryReading
    let deriver: any DashboardHomeDeriving

    init(
        dashboardRepository: any DashboardQueryReading,
        fieldCheckRepository: any HomeFieldCheckQueryReading,
        workingRepository: any HomeWorkingQueryReading,
        deriver: any DashboardHomeDeriving = DashboardHomeDerivationActor()
    ) {
        self.dashboardRepository = dashboardRepository
        self.fieldCheckRepository = fieldCheckRepository
        self.workingRepository = workingRepository
        self.deriver = deriver
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

            return await deriver.makeHomeSnapshot(
                dashboardRecords: dashboard,
                fieldCheckRecords: fieldChecks,
                treatmentTemplates: templates,
                configuration: configuration,
                now: now
            )
        }
    }
}
