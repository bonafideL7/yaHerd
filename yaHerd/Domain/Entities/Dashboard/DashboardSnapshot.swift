import Foundation

struct DashboardSnapshot: Equatable {
    let activeSession: DashboardWorkingSessionSummary?
    let alerts: [DashboardAlert]
    let overview: DashboardOverview
    let analytics: DashboardAnalytics
    let searchableAnimals: [DashboardAnimalItem]
    let pastures: [DashboardPastureItem]
}

struct DashboardAnalytics: Equatable {
    let lifecycleMetrics: [DashboardLifecycleMetric]
    let seasonalCalvingCounts: [DashboardSeasonalCalvingCount]
    let offspringByDam: [DashboardOffspringDamMetric]
    let monthlyMedicalRecords: [DashboardMonthlyMedicalRecordCount]
    let pinkEyeCasesByYear: [DashboardYearCount]
    let statusOutcomesByYear: [DashboardStatusOutcomeYearCount]
}

struct DashboardLifecycleMetric: Identifiable, Hashable {
    let label: String
    let value: Int
    let systemImage: String

    var id: String { label }
}

struct DashboardSeasonalCalvingCount: Identifiable, Hashable {
    let seasonID: String
    let seasonLabel: String
    let year: Int
    let season: DashboardCalvingSeason
    let count: Int

    var id: String { seasonID }
}

enum DashboardCalvingSeason: String, CaseIterable, Hashable {
    case spring
    case fall

    var label: String {
        switch self {
        case .spring: return "Spring"
        case .fall: return "Fall"
        }
    }
}

struct DashboardOffspringDamMetric: Identifiable, Hashable {
    let damID: String
    let damDisplayTagNumber: String
    let offspringCount: Int

    var id: String { damID }
}

struct DashboardMonthlyMedicalRecordCount: Identifiable, Hashable {
    let monthStart: Date
    let treatmentCategory: String
    let count: Int

    var id: String {
        "\(monthStart.timeIntervalSince1970)-\(treatmentCategory)"
    }
}

struct DashboardYearCount: Identifiable, Hashable {
    let year: Int
    let count: Int

    var id: Int { year }
}

struct DashboardStatusOutcomeYearCount: Identifiable, Hashable {
    let year: Int
    let outcome: AnimalStatus
    let count: Int

    var id: String {
        "\(year)-\(outcome.rawValue)"
    }
}

struct DashboardWorkingSessionSummary: Identifiable, Equatable {
    let id: String
    let date: Date
    let sourcePastureName: String?
    let protocolName: String
    let totalQueueItems: Int
    let completedQueueItems: Int
}

struct DashboardOverview: Equatable {
    let activeAnimalCount: Int
    let workingPenCount: Int
    let unassignedAnimalCount: Int
    let overduePregnancyCheckCount: Int
    let overdueTreatmentCount: Int
    let calvingWatchCount: Int
    let pastureCount: Int
    let overstockedPastureCount: Int
    let underutilizedPastureCount: Int
    let rotationReadyPastureCount: Int
}

struct DashboardAnimalItem: Identifiable, Hashable {
    let id: UUID
    let displayTagNumber: String
    let displayTagColorID: UUID?
    let damDisplayTagNumber: String?
    let damDisplayTagColorID: UUID?
    let sex: Sex
    let animalType: AnimalType
    let pastureID: UUID?
    let pastureName: String?
    let location: AnimalLocation
}

struct DashboardPastureItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let activeAnimalCount: Int
    let metrics: PastureMetrics
    let lastGrazedDate: Date?
    let restDays: Int?

    var acres: Double {
        metrics.acres
    }

    var capacityHead: Double? {
        metrics.capacityHead
    }

    var isOverstocked: Bool {
        metrics.isOverstocked
    }

    var isUnderutilized: Bool {
        metrics.isUnderutilized
    }

    var isRestedForRotation: Bool {
        GrazingRotationService.isPastureRested(lastGrazedDate: lastGrazedDate, restDays: restDays)
    }

    var isRotationReady: Bool {
        guard isRestedForRotation, !isOverstocked else { return false }
        guard let utilizationPercent = metrics.utilizationPercent else { return activeAnimalCount == 0 }
        return utilizationPercent < 0.80
    }
}
