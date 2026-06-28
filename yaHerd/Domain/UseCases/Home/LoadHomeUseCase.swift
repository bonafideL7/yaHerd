import Foundation

struct LoadHomeUseCase {
    let dashboardRepository: any DashboardRecordReading
    let fieldCheckRepository: any FieldCheckOverviewReading
    let workingRepository: any WorkingProtocolTemplateListReader
    let service: HomeService

    init(
        dashboardRepository: any DashboardRecordReading,
        fieldCheckRepository: any FieldCheckOverviewReading,
        workingRepository: any WorkingProtocolTemplateListReader,
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
