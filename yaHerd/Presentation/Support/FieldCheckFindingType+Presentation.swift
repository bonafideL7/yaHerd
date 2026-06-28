import Foundation

extension FieldCheckFindingType {
    var systemImage: String {
        switch self {
        case .generalObservation: return "note.text"
        case .pinkEye: return "eye"
        case .limping: return "figure.walk.motion"
        case .coughing: return "wind"
        case .offFeed: return "fork.knife"
        case .injury: return "bandage"
        case .medicalAttention: return "cross.case"
        case .calvingInProgress: return "hourglass"
        case .missingAnimal: return "questionmark.circle"
        case .fenceIssue: return "square.dashed"
        case .waterIssue: return "drop"
        case .movedOutOfPlace: return "arrow.left.arrow.right"
        }
    }
}
