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

    init(id: UUID = UUID(), description: String) {
        self.id = id
        self.description = description
    }
}
