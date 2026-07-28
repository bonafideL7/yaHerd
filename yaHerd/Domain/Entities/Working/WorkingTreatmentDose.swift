import Foundation

struct WorkingTreatmentDose: Codable, Hashable {
    var amount: Double?
    var unit: WorkingTreatmentDoseUnit?
    var route: WorkingTreatmentAdministrationRoute?

    init(
        amount: Double? = nil,
        unit: WorkingTreatmentDoseUnit? = nil,
        route: WorkingTreatmentAdministrationRoute? = nil
    ) {
        self.amount = amount
        self.unit = unit
        self.route = route
    }

    var isEmpty: Bool {
        amount == nil && unit == nil && route == nil
    }

    var formattedDescription: String {
        var components: [String] = []
        if let amount {
            components.append(amount.formatted())
        }
        if let unit {
            components.append(unit.abbreviation)
        }
        if let route {
            components.append(route.label)
        }
        return components.joined(separator: " • ")
    }
}

enum WorkingTreatmentDoseUnit: String, Codable, CaseIterable, Identifiable {
    case milliliter
    case cubicCentimeter
    case milligram
    case gram
    case microgram
    case internationalUnit
    case tablet
    case bolus
    case dose
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .milliliter: return "Milliliters"
        case .cubicCentimeter: return "Cubic Centimeters"
        case .milligram: return "Milligrams"
        case .gram: return "Grams"
        case .microgram: return "Micrograms"
        case .internationalUnit: return "International Units"
        case .tablet: return "Tablets"
        case .bolus: return "Boluses"
        case .dose: return "Doses"
        case .other: return "Other"
        }
    }

    var abbreviation: String {
        switch self {
        case .milliliter: return "mL"
        case .cubicCentimeter: return "cc"
        case .milligram: return "mg"
        case .gram: return "g"
        case .microgram: return "mcg"
        case .internationalUnit: return "IU"
        case .tablet: return "tablet"
        case .bolus: return "bolus"
        case .dose: return "dose"
        case .other: return "other"
        }
    }
}

enum WorkingTreatmentAdministrationRoute: String, Codable, CaseIterable, Identifiable {
    case subcutaneous
    case intramuscular
    case intravenous
    case oral
    case topical
    case intranasal
    case ocular
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .subcutaneous: return "Subcutaneous"
        case .intramuscular: return "Intramuscular"
        case .intravenous: return "Intravenous"
        case .oral: return "Oral"
        case .topical: return "Topical"
        case .intranasal: return "Intranasal"
        case .ocular: return "Ocular"
        case .other: return "Other"
        }
    }

    var abbreviation: String {
        switch self {
        case .subcutaneous: return "SQ"
        case .intramuscular: return "IM"
        case .intravenous: return "IV"
        case .oral: return "PO"
        case .topical: return "Topical"
        case .intranasal: return "IN"
        case .ocular: return "Ocular"
        case .other: return "Other"
        }
    }
}
