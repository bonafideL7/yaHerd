import Foundation

struct PastureMetrics: Hashable {
    let acres: Double
    let activeAnimals: Int
    let targetAcresPerHead: Double?
    let fallbackCapacityHead: Double?

    init(
        acreage: Double?,
        usableAcreage: Double?,
        activeAnimals: Int,
        targetAcresPerHead: Double?,
        fallbackCapacityHead: Double? = nil
    ) {
        self.acres = usableAcreage ?? acreage ?? 0
        self.activeAnimals = activeAnimals
        self.targetAcresPerHead = targetAcresPerHead
        self.fallbackCapacityHead = fallbackCapacityHead
    }

    var acresPerHead: Double {
        guard acres > 0, activeAnimals > 0 else { return 0 }
        return acres / Double(activeAnimals)
    }

    var capacityHead: Double? {
        if let targetAcresPerHead, targetAcresPerHead > 0, acres > 0 {
            let capacity = acres / targetAcresPerHead
            return capacity > 0 ? capacity : nil
        }

        if let fallbackCapacityHead, fallbackCapacityHead > 0 {
            return fallbackCapacityHead
        }

        return nil
    }

    var utilizationPercent: Double? {
        guard let capacityHead, capacityHead > 0 else { return nil }
        return Double(activeAnimals) / capacityHead
    }

    var isOverCapacity: Bool {
        guard let capacityHead else { return false }
        return Double(activeAnimals) > capacityHead
    }

    var utilizationStatus: PastureUtilizationStatus {
        PastureStockingPolicy.status(
            utilizationPercent: utilizationPercent,
            isOverCapacity: isOverCapacity
        )
    }

    var isUnderutilized: Bool {
        utilizationStatus == .underutilized
    }
}
