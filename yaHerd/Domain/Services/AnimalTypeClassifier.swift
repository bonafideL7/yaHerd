import Foundation

enum AnimalTypeClassifier {
    static let calfAgeThresholdInMonths = 12

    static func classify(
        sex: Sex?,
        birthDate: Date,
        hasMaternalOffspring: Bool,
        hasCastrationOrBandingRecord: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AnimalType {
        let ageInMonths = AnimalAgeFormatter.ageInMonths(from: birthDate, now: now, calendar: calendar)
        guard ageInMonths >= calfAgeThresholdInMonths else { return .calf }

        switch sex ?? .unknown {
        case .female:
            return hasMaternalOffspring ? .cow : .heifer
        case .male, .unknown:
            return hasCastrationOrBandingRecord ? .steer : .bull
        }
    }

    static func isCastrationOrBandingTreatment(_ treatment: String) -> Bool {
        let normalizedTreatment = treatment
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalizedTreatment == "castration"
            || normalizedTreatment == "castrated"
            || normalizedTreatment == "banding"
            || normalizedTreatment == "banded"
    }
}
