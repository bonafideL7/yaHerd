import Foundation

struct DashboardRecords {
    let animals: [DashboardAnimalRecord]
    let pastures: [DashboardPastureRecord]
    let workingSessions: [DashboardWorkingSessionRecord]
}

struct DashboardAnimalRecord: Identifiable, Hashable {
    let id: UUID
    let displayTagNumber: String
    let displayTagColorID: UUID?
    let sex: Sex
    let status: AnimalStatus
    let isArchived: Bool
    let pastureID: UUID?
    let pastureName: String?
    let location: AnimalLocation
    let lastPregnancyCheckDate: Date?
    let lastPregnancyStatus: DashboardPregnancyStatus?
    let expectedCalvingDate: Date?
    let lastTreatmentDate: Date?

    var isActiveInHerd: Bool {
        status == .active && !isArchived
    }
}

struct DashboardPastureRecord: Identifiable, Hashable {
    let id: UUID
    let name: String
    let acreage: Double?
    let usableAcreage: Double?
    let targetAcresPerHead: Double?
    let activeAnimalCount: Int
    let lastGrazedDate: Date?

    var metrics: PastureMetrics {
        PastureMetrics(
            acreage: acreage,
            usableAcreage: usableAcreage,
            activeAnimals: activeAnimalCount,
            targetAcresPerHead: targetAcresPerHead
        )
    }
}

struct DashboardWorkingSessionRecord: Identifiable, Hashable {
    let id: String
    let date: Date
    let isActive: Bool
    let sourcePastureName: String?
    let protocolName: String
    let totalQueueItems: Int
    let completedQueueItems: Int
}
