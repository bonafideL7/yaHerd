import Foundation

enum FieldCheckFindingRules {
    static func shouldMarkAnimalMissing(for type: FieldCheckFindingType) -> Bool {
        type == .missingAnimal
    }

    static func defaultSeverity(for type: FieldCheckFindingType) -> FieldCheckFindingSeverity {
        switch type {
        case .injury, .medicalAttention, .calvingInProgress:
            return .critical
        case .pinkEye, .limping, .missingAnimal, .waterIssue, .fenceIssue:
            return .warning
        default:
            return .info
        }
    }
}
