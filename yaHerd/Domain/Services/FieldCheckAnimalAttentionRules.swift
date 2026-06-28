import Foundation

enum FieldCheckAnimalAttentionRules {
    static func shouldNeedAttention(
        animalID: UUID,
        findings: [FieldCheckFindingSnapshot]
    ) -> Bool {
        findings.contains { $0.animalID == animalID }
    }
}
