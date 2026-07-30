import Foundation

actor HomeSnapshotBuilderActor {
    private let service = HomeService()

    func makeSnapshot(
        dashboardRecords: DashboardRecords,
        fieldCheckSessions: [FieldCheckSessionSummary],
        openFindings: [FieldCheckFindingSnapshot],
        treatmentTemplates: [WorkingTreatmentTemplateSummary],
        configuration: DashboardConfiguration,
        now: Date
    ) -> HomeSnapshot {
        PerformanceLog.measure("HomeSnapshotBuilderActor.makeSnapshot") {
            service.makeSnapshot(
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
