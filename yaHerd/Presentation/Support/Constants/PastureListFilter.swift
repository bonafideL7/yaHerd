import Foundation

enum PastureListFilter: CaseIterable, Hashable {
    case all
    case overCapacity
    case underutilized
    case rotationReady
    case missingStockingData

    var label: String {
        switch self {
        case .all:
            return "All"
        case .overCapacity:
            return "Over Capacity"
        case .underutilized:
            return "Low Use"
        case .rotationReady:
            return "Ready"
        case .missingStockingData:
            return "Missing Data"
        }
    }

    var shortLabel: String {
        switch self {
        case .all:
            return "All"
        case .overCapacity:
            return "Over"
        case .underutilized:
            return "Low"
        case .rotationReady:
            return "Ready"
        case .missingStockingData:
            return "Data"
        }
    }
}
