import Foundation

protocol DashboardHomeDeriving: Actor {
    func makeDashboardSnapshot(
        records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date
    ) -> DashboardSnapshot

    func makeDashboardAnimalList(
        kind: DashboardAnimalListKind,
        records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date
    ) -> [DashboardAnimalItem]

    func makeDashboardPastureList(
        records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date
    ) -> [DashboardPastureItem]

    func makeHomeSnapshot(
        dashboardRecords: DashboardRecords,
        fieldCheckRecords: HomeFieldCheckRecords,
        treatmentTemplates: [WorkingTreatmentTemplateSummary],
        configuration: DashboardConfiguration,
        now: Date
    ) -> HomeSnapshot
}

actor DashboardHomeDerivationActor: DashboardHomeDeriving {
    private let dashboardService: DashboardService
    private let homeService: HomeService

    init(
        dashboardService: DashboardService = DashboardService(),
        homeService: HomeService = HomeService()
    ) {
        self.dashboardService = dashboardService
        self.homeService = homeService
    }

    func makeDashboardSnapshot(
        records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date
    ) -> DashboardSnapshot {
        dashboardService.makeSnapshot(
            records: records,
            configuration: configuration,
            now: now
        )
    }

    func makeDashboardAnimalList(
        kind: DashboardAnimalListKind,
        records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date
    ) -> [DashboardAnimalItem] {
        dashboardService.makeAnimalList(
            kind: kind,
            records: records,
            configuration: configuration,
            now: now
        )
    }

    func makeDashboardPastureList(
        records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date
    ) -> [DashboardPastureItem] {
        dashboardService.makeSnapshot(
            records: records,
            configuration: configuration,
            now: now
        ).pastures
    }

    func makeHomeSnapshot(
        dashboardRecords: DashboardRecords,
        fieldCheckRecords: HomeFieldCheckRecords,
        treatmentTemplates: [WorkingTreatmentTemplateSummary],
        configuration: DashboardConfiguration,
        now: Date
    ) -> HomeSnapshot {
        homeService.makeSnapshot(
            dashboardRecords: dashboardRecords,
            fieldCheckSessions: fieldCheckRecords.sessions,
            openFindings: fieldCheckRecords.openFindings,
            treatmentTemplates: treatmentTemplates,
            openFindingCount: fieldCheckRecords.openFindingCount,
            hasFieldCheckHistory: fieldCheckRecords.hasHistory,
            configuration: configuration,
            now: now
        )
    }
}
