import Foundation

struct PastureAnalytics {
    let metrics: PastureMetrics
    let activeAnimals: Int

    init(acreage: Double?, usableAcreage: Double?, aliveAnimals: Int, targetAcresPerHead: Double?, fallbackCapacityHead: Double? = nil) {
        self.activeAnimals = aliveAnimals
        self.metrics = PastureMetrics(
            acreage: acreage,
            usableAcreage: usableAcreage,
            activeAnimals: aliveAnimals,
            targetAcresPerHead: targetAcresPerHead,
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
