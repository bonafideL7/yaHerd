import Foundation

enum PastureListFilter: CaseIterable, Hashable {
    case all
    case overstocked
    case underutilized
    case rotationReady
    case missingStockingData

    var label: String {
        switch self {
        case .all:
            return "All"
        case .overstocked:
            return "Overstocked"
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
        case .overstocked:
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
