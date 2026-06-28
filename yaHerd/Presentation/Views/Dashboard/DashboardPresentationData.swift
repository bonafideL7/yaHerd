import Foundation

struct DashboardPresentationData {
    let lifecycleMetrics: [DashboardLifecycleMetric]
    let seasonalCalvingCounts: [DashboardSeasonalCalvingCount]
    let monthlyMedicalRecords: [DashboardMonthlyMedicalRecordCount]
    let pinkEyeCasesByYear: [DashboardYearCount]
    let offspringByDam: [DashboardOffspringDamMetric]
    let statusOutcomesByYear: [DashboardStatusOutcomeYearCount]
    let animalTypeMixValues: [DashboardCategoryCountValue]
    let sexMixValues: [DashboardCategoryCountValue]
    let herdLocationValues: [DashboardCategoryCountValue]
    let pastureUtilizationValues: [DashboardPastureUtilizationValue]
    let fieldCheckHistoryValues: [DashboardFieldCheckValue]
    let fieldCheckOutcomeValues: [DashboardFieldCheckOutcomeValue]

    init(snapshot: DashboardSnapshot?, fieldCheckSessions: [FieldCheckSessionSummary]) {
        let analytics = snapshot?.analytics
        let animals = snapshot?.searchableAnimals ?? []
        let pastures = snapshot?.pastures ?? []

        lifecycleMetrics = analytics?.lifecycleMetrics ?? []
        seasonalCalvingCounts = analytics?.seasonalCalvingCounts ?? []
        monthlyMedicalRecords = analytics?.monthlyMedicalRecords ?? []
        pinkEyeCasesByYear = analytics?.pinkEyeCasesByYear ?? []
        offspringByDam = analytics?.offspringByDam ?? []
        statusOutcomesByYear = analytics?.statusOutcomesByYear ?? []
        animalTypeMixValues = Self.makeAnimalTypeMixValues(from: animals)
        sexMixValues = Self.makeSexMixValues(from: animals)
        herdLocationValues = Self.makeHerdLocationValues(from: animals)
        pastureUtilizationValues = Self.makePastureUtilizationValues(from: pastures)
        fieldCheckHistoryValues = Self.makeFieldCheckHistoryValues(from: fieldCheckSessions)
        fieldCheckOutcomeValues = Self.makeFieldCheckOutcomeValues(from: fieldCheckHistoryValues)
    }

    var pastureUtilizationChartUpperBound: Double {
        let maxValue = pastureUtilizationValues.map(\.utilizationPercent).max() ?? 100
        return max(110, (maxValue * 1.15).rounded(.up))
    }

    func selectedPastureUtilizationValue(named pastureName: String?) -> DashboardPastureUtilizationValue? {
        guard let pastureName else { return nil }
        return pastureUtilizationValues.first { $0.name == pastureName }
    }

    private static func makeAnimalTypeMixValues(from animals: [DashboardAnimalItem]) -> [DashboardCategoryCountValue] {
        AnimalType.allCases
            .map { type in
                DashboardCategoryCountValue(
                    label: type.label,
                    count: animals.filter { $0.animalType == type }.count
                )
            }
            .filter { $0.count > 0 }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
    }

    private static func makeSexMixValues(from animals: [DashboardAnimalItem]) -> [DashboardCategoryCountValue] {
        Sex.allCases
            .map { sex in
                DashboardCategoryCountValue(
                    label: sex.label,
                    count: animals.filter { $0.sex == sex }.count
                )
            }
            .filter { $0.count > 0 }
    }

    private static func makeHerdLocationValues(from animals: [DashboardAnimalItem]) -> [DashboardCategoryCountValue] {
        [
            DashboardCategoryCountValue(
                label: "Pasture assigned",
                count: animals.filter { $0.location == .pasture && $0.pastureID != nil }.count
            ),
            DashboardCategoryCountValue(
                label: "Working pen",
                count: animals.filter { $0.location == .workingPen }.count
            ),
            DashboardCategoryCountValue(
                label: "Pasture unassigned",
                count: animals.filter { $0.location == .pasture && $0.pastureID == nil }.count
            )
        ]
    }

    private static func makePastureUtilizationValues(from pastures: [DashboardPastureItem]) -> [DashboardPastureUtilizationValue] {
        pastures
            .compactMap { pasture in
                guard pasture.acres > 0,
                      let utilization = pasture.metrics.utilizationPercent else { return nil }

                return DashboardPastureUtilizationValue(
                    id: pasture.id,
                    name: pasture.name,
                    acres: pasture.acres,
                    utilizationPercent: utilization * 100,
                    activeAnimalCount: pasture.activeAnimalCount,
                    statusLabel: pastureStatusLabel(for: pasture)
                )
            }
            .sorted { lhs, rhs in
                if lhs.utilizationPercent != rhs.utilizationPercent { return lhs.utilizationPercent > rhs.utilizationPercent }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private static func makeFieldCheckHistoryValues(from sessions: [FieldCheckSessionSummary]) -> [DashboardFieldCheckValue] {
        sessions
            .sorted { $0.startedAt < $1.startedAt }
            .suffix(12)
            .map { session in
                DashboardFieldCheckValue(
                    id: session.id,
                    sessionLabel: session.displayTitle,
                    startedAt: session.startedAt,
                    expectedHeadCount: session.expectedHeadCountSnapshot,
                    totalSeen: session.totalSeen,
                    flaggedAnimalCount: session.flaggedAnimalCount,
                    missingAnimalCount: session.missingAnimalCount,
                    openFindingsCount: session.openFindingsCount
                )
            }
    }

    private static func makeFieldCheckOutcomeValues(from historyValues: [DashboardFieldCheckValue]) -> [DashboardFieldCheckOutcomeValue] {
        historyValues.flatMap { item in
            [
                DashboardFieldCheckOutcomeValue(sessionID: item.id, sessionLabel: item.shortSessionLabel, metric: "Flagged", value: item.flaggedAnimalCount),
                DashboardFieldCheckOutcomeValue(sessionID: item.id, sessionLabel: item.shortSessionLabel, metric: "Missing", value: item.missingAnimalCount),
                DashboardFieldCheckOutcomeValue(sessionID: item.id, sessionLabel: item.shortSessionLabel, metric: "Findings", value: item.openFindingsCount)
            ]
        }
    }

    private static func pastureStatusLabel(for pasture: DashboardPastureItem) -> String {
        if pasture.isRotationReady { return "Ready" }
        if pasture.isUnderutilized { return "Low" }
        return "Normal"
    }
}

struct DashboardCategoryCountValue: Identifiable, Hashable {
    let label: String
    let count: Int

    var id: String { label }
}

struct DashboardPastureUtilizationValue: Identifiable, Hashable {
    let id: UUID
    let name: String
    let acres: Double
    let utilizationPercent: Double
    let activeAnimalCount: Int
    let statusLabel: String
}

struct DashboardFieldCheckValue: Identifiable, Hashable {
    let id: UUID
    let sessionLabel: String
    let startedAt: Date
    let expectedHeadCount: Int
    let totalSeen: Int
    let flaggedAnimalCount: Int
    let missingAnimalCount: Int
    let openFindingsCount: Int

    var shortSessionLabel: String {
        let dateText = startedAt.formatted(.dateTime.month(.abbreviated).day())
        return sessionLabel == "Pasture Check" ? dateText : "\(sessionLabel) \(dateText)"
    }
}

struct DashboardFieldCheckOutcomeValue: Identifiable, Hashable {
    let sessionID: UUID
    let sessionLabel: String
    let metric: String
    let value: Int

    var id: String {
        "\(sessionID.uuidString)-\(metric)"
    }
}
