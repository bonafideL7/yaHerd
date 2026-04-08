import Foundation

struct PastureDetailSnapshot: Identifiable, Equatable {
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
