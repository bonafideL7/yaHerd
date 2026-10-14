import Foundation

struct HomeService {
    private let dashboardService: DashboardService

    init(dashboardService: DashboardService = DashboardService()) {
        self.dashboardService = dashboardService
    }

    func makeSnapshot(
        dashboardRecords: DashboardRecords,
        fieldCheckSessions: [FieldCheckSessionSummary],
        openFindings: [FieldCheckFindingSnapshot],
        treatmentTemplates: [WorkingTreatmentTemplateSummary],
        openFindingCount: Int? = nil,
        hasFieldCheckHistory: Bool? = nil,
        configuration: DashboardConfiguration,
        now: Date = .now
    ) -> HomeSnapshot {
        let dashboardSnapshot = dashboardService.makeSnapshot(
            records: dashboardRecords,
            configuration: configuration,
            now: now
        )
        let activeAnimalRecords = sortedActiveAnimalRecords(from: dashboardRecords.animals)
        let activeCheckSessions = fieldCheckSessions
            .filter { !$0.isCompleted }
            .sorted { left, right in
                if left.startedAt != right.startedAt { return left.startedAt > right.startedAt }
                return left.id.uuidString < right.id.uuidString
            }

        return HomeSnapshot(
            activeSession: dashboardSnapshot.activeSession,
            alerts: dashboardSnapshot.alerts,
            activeAnimalRecords: activeAnimalRecords,
            activeCheckSessions: activeCheckSessions,
            openFindings: openFindings,
            openFindingCount: openFindingCount ?? openFindings.count,
            flaggedCheckSessions: flaggedCheckSessions(from: fieldCheckSessions),
            missingCheckSessions: missingCheckSessions(from: fieldCheckSessions),
            pastureCheckStartPastures: dashboardSnapshot.pastures,
            workingPenAnimalRecords: activeAnimalRecords.filter { $0.location == .workingPen },
            rotationReadyPastures: rotationReadyPastures(from: dashboardSnapshot.pastures),
            underutilizedPastures: underutilizedPastures(from: dashboardSnapshot.pastures),
            pasturesMissingStockingData: pasturesMissingStockingData(from: dashboardSnapshot.pastures),
            unassignedAnimalRecords: activeAnimalRecords.filter { $0.location == .pasture && $0.pastureID == nil },
            missingTagAnimals: activeAnimalRecords.filter { $0.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            unknownSexAnimals: activeAnimalRecords.filter { $0.sex == .unknown },
            archivedActiveRecords: archivedActiveRecords(from: dashboardRecords.animals),
            hasPastures: !dashboardRecords.pastures.isEmpty,
            hasActiveAnimals: dashboardRecords.animals.contains { $0.isActiveInHerd },
            hasFieldCheckHistory: hasFieldCheckHistory ?? !fieldCheckSessions.isEmpty,
            hasWorkingSessionHistory: !dashboardRecords.workingSessions.isEmpty,
            hasWorkingTreatmentTemplates: !treatmentTemplates.isEmpty
        )
    }

    private func sortedActiveAnimalRecords(from records: [DashboardAnimalRecord]) -> [DashboardAnimalRecord] {
        records
            .filter(\.isActiveInHerd)
            .sorted { lhs, rhs in
                let order = lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber)
                if order != .orderedSame { return order == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func archivedActiveRecords(from records: [DashboardAnimalRecord]) -> [DashboardAnimalRecord] {
        records
            .filter { $0.isArchived && $0.status == .active }
            .sorted { lhs, rhs in
                let order = lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber)
                if order != .orderedSame { return order == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func flaggedCheckSessions(from sessions: [FieldCheckSessionSummary]) -> [FieldCheckSessionSummary] {
        sessions
            .filter { $0.flaggedAnimalCount > 0 }
            .sorted(by: unfinishedFirstThenNewest)
    }

    private func missingCheckSessions(from sessions: [FieldCheckSessionSummary]) -> [FieldCheckSessionSummary] {
        sessions
            .filter { $0.missingAnimalCount > 0 }
            .sorted(by: unfinishedFirstThenNewest)
    }

    private func unfinishedFirstThenNewest(
        _ left: FieldCheckSessionSummary,
        _ right: FieldCheckSessionSummary
    ) -> Bool {
        if left.isCompleted != right.isCompleted {
            return !left.isCompleted
        }
        if left.startedAt != right.startedAt { return left.startedAt > right.startedAt }
        return left.id.uuidString < right.id.uuidString
    }

    private func rotationReadyPastures(from pastures: [DashboardPastureItem]) -> [DashboardPastureItem] {
        pastures
            .filter(\.isRotationReady)
            .sorted { lhs, rhs in
                if lhs.activeAnimalCount != rhs.activeAnimalCount {
                    return lhs.activeAnimalCount < rhs.activeAnimalCount
                }
                let order = lhs.name.localizedStandardCompare(rhs.name)
                if order != .orderedSame { return order == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func underutilizedPastures(from pastures: [DashboardPastureItem]) -> [DashboardPastureItem] {
        pastures
            .filter(\.isUnderutilized)
            .sorted { lhs, rhs in
                let leftUtilization = lhs.metrics.utilizationPercent ?? 0
                let rightUtilization = rhs.metrics.utilizationPercent ?? 0
                if leftUtilization != rightUtilization { return leftUtilization < rightUtilization }
                let order = lhs.name.localizedStandardCompare(rhs.name)
                if order != .orderedSame { return order == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func pasturesMissingStockingData(from pastures: [DashboardPastureItem]) -> [DashboardPastureItem] {
        pastures
            .filter { pasture in
                pasture.acres <= 0 || pasture.metrics.targetAcresPerHead == nil
            }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                if order != .orderedSame { return order == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }
}
