import Foundation

extension AnimalStatus {
    var systemImage: String {
        switch self {
        case .active: return "checkmark.circle.fill"
        case .sold: return "dollarsign.circle.fill"
        case .dead: return "xmark.circle.fill"
        }
    }
}
