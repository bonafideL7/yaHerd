import Foundation

struct AnimalInput: Hashable {
    let name: String
    let tagNumber: String
    let tagColorID: UUID?
    let sex: Sex
    let birthDate: Date
    let status: AnimalStatus
    let pastureID: UUID?
    let sireID: UUID?
    let damID: UUID?
    let distinguishingFeatures: [DistinguishingFeature]
    let saleDate: Date?
    let salePrice: Double?
    let reasonSold: String?
    let deathDate: Date?
    let causeOfDeath: String?
    let statusReferenceID: UUID?
}
