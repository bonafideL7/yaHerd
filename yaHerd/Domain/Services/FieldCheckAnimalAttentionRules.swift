import Foundation

enum FieldCheckAnimalAttentionRules {
    static func shouldNeedAttention(
        animalID: UUID,
        findings: [FieldCheckFindingSnapshot]
    ) -> Bool {
        findings.contains { finding in
            finding.animalID == animalID && finding.status != .resolved
        }
    }
}
