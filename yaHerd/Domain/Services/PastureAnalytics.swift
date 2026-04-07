import Foundation

struct PastureAnalytics {
    let metrics: PastureMetrics
    let activeAnimals: Int

    init(pasture: Pasture, aliveAnimals: Int, fallbackCapacityHead: Double? = nil) {
        self.activeAnimals = aliveAnimals
        self.metrics = PastureMetrics(
            acreage: pasture.acreage,
            usableAcreage: pasture.usableAcreage,
            activeAnimals: aliveAnimals,
            targetAcresPerHead: pasture.targetAcresPerHead,
            fallbackCapacityHead: fallbackCapacityHead
        )
    }

    var acres: Double { metrics.acres }
    var acresPerHead: Double { metrics.acresPerHead }
    var targetAcresPerHead: Double? { metrics.targetAcresPerHead }
    var capacityHead: Double? { metrics.capacityHead }
    var utilizationPercent: Double? { metrics.utilizationPercent }
    var isOverstocked: Bool { metrics.isOverstocked }
    var isUnderutilized: Bool { metrics.isUnderutilized }
}
