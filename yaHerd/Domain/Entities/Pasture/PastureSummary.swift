import Foundation

struct PastureSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let acreage: Double?
    let usableAcreage: Double?
    let targetAcresPerHead: Double?
    let activeAnimalCount: Int
    let sortOrder: Int
    let lastGrazedDate: Date?
    let groupID: UUID?
    let groupName: String?
    let restDays: Int?

    var metrics: PastureMetrics {
        PastureMetrics(
            acreage: acreage,
            usableAcreage: usableAcreage,
            activeAnimals: activeAnimalCount,
            targetAcresPerHead: targetAcresPerHead
        )
    }

    var acres: Double {
        metrics.acres
    }

    var capacityHead: Double? {
        metrics.capacityHead
    }

    var isOverCapacity: Bool {
        metrics.isOverCapacity
    }

    var isUnderutilized: Bool {
        metrics.isUnderutilized
    }

    var isMissingStockingData: Bool {
        acres <= 0 || targetAcresPerHead == nil
    }

    var isRestedForRotation: Bool {
        GrazingRotationService.isPastureRested(lastGrazedDate: lastGrazedDate, restDays: restDays)
    }

    var isRotationReady: Bool {
        PastureStockingPolicy.isRotationReady(
            isRestedForRotation: isRestedForRotation,
            isOverCapacity: isOverCapacity,
            utilizationPercent: metrics.utilizationPercent,
            activeAnimalCount: activeAnimalCount
        )
    }
}
