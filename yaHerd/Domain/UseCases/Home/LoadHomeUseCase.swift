import Foundation

struct LoadHomeUseCase {
    let dashboardRepository: any DashboardRepository
    let fieldCheckRepository: any FieldCheckRepository
    let workingRepository: any WorkingRepository
    let service: HomeService

    init(
        dashboardRepository: any DashboardRepository,
        fieldCheckRepository: any FieldCheckRepository,
        workingRepository: any WorkingRepository,
        service: HomeService = HomeService()
    ) {
        self.dashboardRepository = dashboardRepository
        self.fieldCheckRepository = fieldCheckRepository
        self.workingRepository = workingRepository
        self.service = service
    }

    func execute(configuration: DashboardConfiguration, now: Date = .now) throws -> HomeSnapshot {
        let dashboardRecords = try dashboardRepository.fetchDashboardRecords()
        let fieldCheckSessions = try fieldCheckRepository.fetchSessions()
        let openFindings = try fieldCheckRepository.fetchOpenFindings(limit: 0)
        let protocolTemplates = try workingRepository.fetchTemplates()

        return service.makeSnapshot(
            dashboardRecords: dashboardRecords,
            fieldCheckSessions: fieldCheckSessions,
            openFindings: openFindings,
            protocolTemplates: protocolTemplates,
            configuration: configuration,
            now: now
        )
    }
}
