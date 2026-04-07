import Foundation

struct PastureSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let acreage: Double?
    let usableAcreage: Double?
    let targetAcresPerHead: Double?
    let activeAnimalCount: Int

    var metrics: PastureMetrics {
        PastureMetrics(
            acreage: acreage,
            usableAcreage: usableAcreage,
            activeAnimals: activeAnimalCount,
            targetAcresPerHead: targetAcresPerHead
        )
    }
}
