import Foundation

enum FieldCheckFindingType: String, Codable, CaseIterable, Identifiable, Hashable {
    case generalObservation
    case pinkEye
    case limping
    case coughing
    case offFeed
    case injury
    case medicalAttention
    case calvingInProgress
    case missingAnimal
    case fenceIssue
    case waterIssue
    case movedOutOfPlace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .generalObservation: return "Observation"
        case .pinkEye: return "Pink Eye"
        case .limping: return "Limping"
        case .coughing: return "Coughing"
        case .offFeed: return "Off Feed"
        case .injury: return "Injury"
        case .medicalAttention: return "Needs Treatment"
        case .calvingInProgress: return "Calving"
        case .missingAnimal: return "Missing Animal"
        case .fenceIssue: return "Fence Issue"
        case .waterIssue: return "Water Issue"
        case .movedOutOfPlace: return "Wrong Pasture"
        }
    }
}

enum FieldCheckFindingSeverity: String, Codable, CaseIterable, Identifiable, Hashable {
    case info
    case warning
    case critical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Watch"
        case .critical: return "Urgent"
        }
    }
}

enum FieldCheckFindingStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case open
    case monitoring
    case resolved

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: return "Open"
        case .monitoring: return "Monitoring"
        case .resolved: return "Resolved"
        }
    }
}
