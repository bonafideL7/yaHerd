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
