import Foundation

enum Sex: String, Codable, CaseIterable {
    case female
    case male
    case unknown

    var label: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .unknown: return "Unknown"
        }
    }
}

enum AnimalStatus: String, Codable, CaseIterable {
    case active
    case sold
    case dead

    var label: String {
        switch self {
        case .active: return "Active"
        case .sold: return "Sold"
        case .dead: return "Dead"
        }
    }

    var systemImage: String {
        switch self {
        case .active: return "checkmark.circle.fill"
        case .sold: return "dollarsign.circle.fill"
        case .dead: return "xmark.circle.fill"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue.lowercased() {
        case "active", "alive":
            self = .active
        case "sold":
            self = .sold
        case "dead", "deceased":
            self = .dead
        case "reference":
            self = .active
        default:
            self = .active
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum AnimalLocation: String, Codable, CaseIterable {
    case pasture
    case workingPen
}

struct DistinguishingFeature: Codable, Hashable, Identifiable {
    var id: UUID
    var description: String
    var order: Int

    init(id: UUID = UUID(), description: String, order: Int) {
        self.id = id
        self.description = description
        self.order = order
    }
}

extension Collection where Element == DistinguishingFeature {
    var orderedDistinguishingFeatures: [DistinguishingFeature] {
        enumerated()
            .sorted { lhs, rhs in
                if lhs.element.order != rhs.element.order {
                    return lhs.element.order < rhs.element.order
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    var normalizedDistinguishingFeatureOrder: [DistinguishingFeature] {
        orderedDistinguishingFeatures
            .enumerated()
            .map { index, feature in
                DistinguishingFeature(
                    id: feature.id,
                    description: feature.description,
                    order: index
                )
            }
    }

    var firstOrderedDistinguishingFeatureDescription: String? {
        orderedDistinguishingFeatures
            .lazy
            .map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}


enum AnimalType: String, Codable, CaseIterable {
    case calf
    case heifer
    case steer
    case cow
    case bull

    var label: String {
        switch self {
        case .calf: return "Calf"
        case .heifer: return "Heifer"
        case .steer: return "Steer"
        case .cow: return "Cow"
        case .bull: return "Bull"
        }
    }
}
