import Foundation

struct DashboardSnapshot: Equatable {
    let activeSession: DashboardWorkingSessionSummary?
    let alerts: [DashboardAlert]
    let overview: DashboardOverview
    let searchableAnimals: [DashboardAnimalItem]
    let pastures: [DashboardPastureItem]
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
    let pastureCount: Int
}

struct DashboardAnimalItem: Identifiable, Hashable {
    let id: UUID
    let displayTagNumber: String
    let displayTagColorID: UUID?
    let damDisplayTagNumber: String?
    let damDisplayTagColorID: UUID?
    let sex: Sex
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
}
