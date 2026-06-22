import Foundation

struct HomeService {
    private let dashboardService: DashboardService
    private let pastureCheckIntervalDays = 7

    init(dashboardService: DashboardService = DashboardService()) {
        self.dashboardService = dashboardService
    }

    func makeSnapshot(
        dashboardRecords: DashboardRecords,
        fieldCheckSessions: [FieldCheckSessionSummary],
        openFindings: [FieldCheckFindingSnapshot],
        protocolTemplates: [WorkingProtocolTemplateSummary],
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
            .sorted { $0.startedAt > $1.startedAt }

        return HomeSnapshot(
            activeSession: dashboardSnapshot.activeSession,
            alerts: dashboardSnapshot.alerts,
            activeAnimalRecords: activeAnimalRecords,
            activeCheckSessions: activeCheckSessions,
            openFindings: openFindings,
            flaggedCheckSessions: flaggedCheckSessions(from: fieldCheckSessions),
            missingCheckSessions: missingCheckSessions(from: fieldCheckSessions),
            pastureCheckDueItems: pastureCheckDueItems(
                pastures: dashboardSnapshot.pastures,
                fieldCheckSessions: fieldCheckSessions,
                activeCheckSessions: activeCheckSessions,
                now: now
            ),
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
            hasFieldCheckHistory: !fieldCheckSessions.isEmpty,
            hasWorkingProtocolTemplates: !protocolTemplates.isEmpty
        )
    }

    private func sortedActiveAnimalRecords(from records: [DashboardAnimalRecord]) -> [DashboardAnimalRecord] {
        records
            .filter(\.isActiveInHerd)
            .sorted { lhs, rhs in
                lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
            }
    }

    private func archivedActiveRecords(from records: [DashboardAnimalRecord]) -> [DashboardAnimalRecord] {
        records
            .filter { $0.isArchived && $0.status == .active }
            .sorted { lhs, rhs in
                lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
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
        return left.startedAt > right.startedAt
    }

    private func pastureCheckDueItems(
        pastures: [DashboardPastureItem],
        fieldCheckSessions: [FieldCheckSessionSummary],
        activeCheckSessions: [FieldCheckSessionSummary],
        now: Date
    ) -> [HomePastureCheckDueItem] {
        let activePastureIDs = Set(activeCheckSessions.compactMap(\.pastureID))
        let latestCheckDateByPastureID = Dictionary(
            grouping: fieldCheckSessions.compactMap { session -> (UUID, Date)? in
                guard session.isCompleted, let pastureID = session.pastureID else { return nil }
                return (pastureID, session.startedAt)
            },
            by: { $0.0 }
        ).mapValues { pairs in
            pairs.map(\.1).max() ?? .distantPast
        }
        let dueBeforeDate = Calendar.current.date(byAdding: .day, value: -pastureCheckIntervalDays, to: now) ?? .distantPast

        return pastures
            .filter { pasture in
                !activePastureIDs.contains(pasture.id)
                    && (latestCheckDateByPastureID[pasture.id] ?? .distantPast) < dueBeforeDate
            }
            .map { pasture in
                HomePastureCheckDueItem(
                    id: pasture.id,
                    name: pasture.name,
                    activeAnimalCount: pasture.activeAnimalCount,
                    lastCheckDate: latestCheckDateByPastureID[pasture.id]
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.lastCheckDate, rhs.lastCheckDate) {
                case (nil, nil):
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                case (nil, _):
                    return true
                case (_, nil):
                    return false
                case let (left?, right?):
                    if left != right { return left < right }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
    }

    private func rotationReadyPastures(from pastures: [DashboardPastureItem]) -> [DashboardPastureItem] {
        pastures
            .filter(\.isRotationReady)
            .sorted { lhs, rhs in
                if lhs.activeAnimalCount != rhs.activeAnimalCount {
                    return lhs.activeAnimalCount < rhs.activeAnimalCount
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func underutilizedPastures(from pastures: [DashboardPastureItem]) -> [DashboardPastureItem] {
        pastures
            .filter(\.isUnderutilized)
            .sorted { lhs, rhs in
                let leftUtilization = lhs.metrics.utilizationPercent ?? 0
                let rightUtilization = rhs.metrics.utilizationPercent ?? 0
                if leftUtilization != rightUtilization { return leftUtilization < rightUtilization }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func pasturesMissingStockingData(from pastures: [DashboardPastureItem]) -> [DashboardPastureItem] {
        pastures
            .filter { pasture in
                pasture.acres <= 0 || pasture.metrics.targetAcresPerHead == nil
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
