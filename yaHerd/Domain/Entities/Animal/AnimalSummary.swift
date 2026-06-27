import Foundation

struct AnimalSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let displayTagNumber: String
    let displayTagColorID: UUID?
    let damDisplayTagNumber: String?
    let damDisplayTagColorID: UUID?
    let sex: Sex
    let animalType: AnimalType
    let firstDistinguishingFeature: String?
    let birthDate: Date
    let status: AnimalStatus
    let isArchived: Bool
    let pastureID: UUID?
    let pastureName: String?
    let location: AnimalLocation
    let lastPregnancyCheckDate: Date?
    let lastPregnancyStatus: AnimalPregnancyStatus?
    let expectedCalvingDate: Date?
    let lastTreatmentDate: Date?

    init(
        id: UUID,
        name: String,
        displayTagNumber: String,
        displayTagColorID: UUID?,
        damDisplayTagNumber: String?,
        damDisplayTagColorID: UUID?,
        sex: Sex,
        animalType: AnimalType,
        firstDistinguishingFeature: String?,
        birthDate: Date,
        status: AnimalStatus,
        isArchived: Bool,
        pastureID: UUID?,
        pastureName: String?,
        location: AnimalLocation,
        lastPregnancyCheckDate: Date? = nil,
        lastPregnancyStatus: AnimalPregnancyStatus? = nil,
        expectedCalvingDate: Date? = nil,
        lastTreatmentDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.displayTagNumber = displayTagNumber
        self.displayTagColorID = displayTagColorID
        self.damDisplayTagNumber = damDisplayTagNumber
        self.damDisplayTagColorID = damDisplayTagColorID
        self.sex = sex
        self.animalType = animalType
        self.firstDistinguishingFeature = firstDistinguishingFeature
        self.birthDate = birthDate
        self.status = status
        self.isArchived = isArchived
        self.pastureID = pastureID
        self.pastureName = pastureName
        self.location = location
        self.lastPregnancyCheckDate = lastPregnancyCheckDate
        self.lastPregnancyStatus = lastPregnancyStatus
        self.expectedCalvingDate = expectedCalvingDate
        self.lastTreatmentDate = lastTreatmentDate
    }

    var typeAndFeatureLabel: String {
        guard let firstDistinguishingFeature, !firstDistinguishingFeature.isEmpty else {
            return animalType.label
        }

        return "\(animalType.label) • \(firstDistinguishingFeature)"
    }

    var age: String {
        AnimalAgeFormatter.string(from: birthDate, style: .compact)
    }
}
