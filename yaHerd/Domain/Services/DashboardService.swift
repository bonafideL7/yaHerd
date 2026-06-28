import Foundation

struct DashboardService {
    private let analyticsService: DashboardAnalyticsService

    init(analyticsService: DashboardAnalyticsService = DashboardAnalyticsService()) {
        self.analyticsService = analyticsService
    }

    func makeSnapshot(
        records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date = .now
    ) -> DashboardSnapshot {
        let searchableAnimals = sortedAnimalItems(from: activeAnimals(in: records))
        let pastures = sortedPastureItems(from: records.pastures, configuration: configuration)

        return DashboardSnapshot(
            activeSession: activeSession(in: records),
            alerts: alerts(in: records, configuration: configuration, now: now),
            overview: overview(in: records, configuration: configuration, now: now),
            analytics: analyticsService.makeAnalytics(in: records, now: now),
            searchableAnimals: searchableAnimals,
            pastures: pastures
        )
    }

    func makeAnimalList(
        kind: DashboardAnimalListKind,
        records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date = .now
    ) -> [DashboardAnimalItem] {
        let animals: [DashboardAnimalRecord]

        switch kind {
        case .active:
            animals = activeAnimals(in: records)
        case .workingPen:
            animals = activeAnimals(in: records).filter { $0.location == .workingPen }
        case .unassigned:
            animals = unassignedAnimals(in: records)
        }

        return sortedAnimalItems(from: animals)
    }

    func filterPastures(
        _ items: [DashboardPastureItem],
        filter: DashboardPastureFilter
    ) -> [DashboardPastureItem] {
        switch filter {
        case .all:
            return items
        case .underutilized:
            return items.filter { $0.isUnderutilized }
        case .rotationReady:
            return items.filter { $0.isRotationReady }
        }
    }


    private func overview(
        in records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date
    ) -> DashboardOverview {
        let active = activeAnimals(in: records)
        let pastures = sortedPastureItems(from: records.pastures, configuration: configuration)

        return DashboardOverview(
            activeAnimalCount: active.count,
            workingPenCount: active.filter { $0.location == .workingPen }.count,
            unassignedAnimalCount: unassignedAnimals(in: records).count,
            pastureCount: records.pastures.count,
            underutilizedPastureCount: pastures.filter { $0.isUnderutilized }.count,
            rotationReadyPastureCount: pastures.filter { $0.isRotationReady }.count
        )
    }

    private func activeAnimals(in records: DashboardRecords) -> [DashboardAnimalRecord] {
        records.animals.filter { $0.isActiveInHerd }
    }

    private func unassignedAnimals(in records: DashboardRecords) -> [DashboardAnimalRecord] {
        activeAnimals(in: records).filter { animal in
            animal.location == .pasture && animal.pastureID == nil
        }
    }

    private func activeSession(in records: DashboardRecords) -> DashboardWorkingSessionSummary? {
        records.workingSessions
            .sorted { lhs, rhs in
                lhs.date > rhs.date
            }
            .first(where: { $0.isActive })
            .map { session in
                DashboardWorkingSessionSummary(
                    id: session.id,
                    date: session.date,
                    sourcePastureName: session.sourcePastureName,
                    protocolName: session.protocolName,
                    totalQueueItems: session.totalQueueItems,
                    completedQueueItems: session.completedQueueItems
                )
            }
    }

    private func sortedAnimalItems(from animals: [DashboardAnimalRecord]) -> [DashboardAnimalItem] {
        animals
            .map { animal in
                DashboardAnimalItem(
                    id: animal.id,
                    displayTagNumber: animal.displayTagNumber,
                    displayTagColorID: animal.displayTagColorID,
                    damDisplayTagNumber: animal.damDisplayTagNumber,
                    damDisplayTagColorID: animal.damDisplayTagColorID,
                    sex: animal.sex,
                    animalType: animal.animalType,
                    pastureID: animal.pastureID,
                    pastureName: animal.pastureName,
                    location: animal.location
                )
            }
            .sorted { lhs, rhs in
                lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
            }
    }

    private func sortedPastureItems(
        from pastures: [DashboardPastureRecord],
        configuration: DashboardConfiguration
    ) -> [DashboardPastureItem] {
        pastures
            .map { pasture in
                DashboardPastureItem(
                    id: pasture.id,
                    name: pasture.name,
                    activeAnimalCount: pasture.activeAnimalCount,
                    metrics: PastureMetrics(
                        acreage: pasture.acreage,
                        usableAcreage: pasture.usableAcreage,
                        activeAnimals: pasture.activeAnimalCount,
                        targetAcresPerHead: pasture.targetAcresPerHead,
                        fallbackCapacityHead: nil
                    ),
                    lastGrazedDate: pasture.lastGrazedDate,
                    restDays: pasture.restDays
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func alerts(
        in records: DashboardRecords,
        configuration: DashboardConfiguration,
        now: Date
    ) -> [DashboardAlert] {
        var alerts: [DashboardAlert] = []

        let unassigned = unassignedAnimals(in: records)
        if !unassigned.isEmpty {
            alerts.append(
                DashboardAlert(
                    title: "\(unassigned.count) animals not assigned to a pasture",
                    message: "Assign them to avoid management issues.",
                    icon: "map-pin-off",
                    severity: .warning,
                    destination: .animalList(.unassigned)
                )
            )
        }

        return alerts.sorted { lhs, rhs in
            lhs.severityOrder > rhs.severityOrder
        }
    }
}
