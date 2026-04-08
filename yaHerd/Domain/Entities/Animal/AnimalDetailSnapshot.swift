import Foundation

struct AnimalDetailSnapshot: Identifiable, Hashable {
    let id: UUID
    let name: String
    let displayTagNumber: String
    let displayTagColorID: UUID?
    let sex: Sex
    let birthDate: Date
    let status: AnimalStatus
    let pastureID: UUID?
    let pastureName: String?
    let sire: String?
    let dam: String?
    let distinguishingFeatures: [DistinguishingFeature]
    let saleDate: Date?
    let salePrice: Double?
    let reasonSold: String?
    let deathDate: Date?
    let causeOfDeath: String?
    let statusReferenceID: UUID?
    let statusReferenceName: String?
    let isArchived: Bool
    let archivedAt: Date?
    let archiveReason: String?
    let activeTags: [AnimalTagSnapshot]
    let inactiveTags: [AnimalTagSnapshot]
    let location: AnimalLocation

    var age: String {
        AnimalSummary(
            id: id,
            name: name,
            displayTagNumber: displayTagNumber,
            displayTagColorID: displayTagColorID,
            sex: sex,
            birthDate: birthDate,
            status: status,
            isArchived: isArchived,
            pastureID: pastureID,
            pastureName: pastureName,
            location: location
        ).age
    }
}
