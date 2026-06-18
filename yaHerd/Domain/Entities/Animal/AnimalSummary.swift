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
    let lastPregnancyStatus: DashboardPregnancyStatus?
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
        lastPregnancyStatus: DashboardPregnancyStatus? = nil,
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
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let birth = calendar.startOfDay(for: birthDate)

        guard birth <= today else { return "1d" }

        let yearMonth = calendar.dateComponents([.year, .month], from: birth, to: today)
        if let years = yearMonth.year, years >= 1 {
            let months = yearMonth.month ?? 0
            return months > 0 ? "\(years)y \(months)m" : "\(years)y"
        }

        let months = calendar.dateComponents([.month], from: birth, to: today).month ?? 0
        if months >= 1 {
            return "\(months)m"
        }

        let days = calendar.dateComponents([.day], from: birth, to: today).day ?? 0
        return "\(max(days, 1))d"
    }
}
