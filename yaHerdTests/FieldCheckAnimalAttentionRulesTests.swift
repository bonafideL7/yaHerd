import XCTest
@testable import yaHerd

final class FieldCheckAnimalAttentionRulesTests: XCTestCase {
    func testShouldNeedAttentionWhenFindingExistsForAnimal() {
        let animalID = UUID()
        let findings = [makeFinding(animalID: animalID)]

        XCTAssertTrue(
            FieldCheckAnimalAttentionRules.shouldNeedAttention(
                animalID: animalID,
                findings: findings
            )
        )
    }

    func testShouldNotNeedAttentionWhenFindingsBelongToDifferentAnimal() {
        let animalID = UUID()
        let findings = [makeFinding(animalID: UUID())]

        XCTAssertFalse(
            FieldCheckAnimalAttentionRules.shouldNeedAttention(
                animalID: animalID,
                findings: findings
            )
        )
    }

    func testShouldNotNeedAttentionWhenFindingIsUnlinked() {
        let animalID = UUID()
        let findings = [makeFinding(animalID: nil)]

        XCTAssertFalse(
            FieldCheckAnimalAttentionRules.shouldNeedAttention(
                animalID: animalID,
                findings: findings
            )
        )
    }

    private func makeFinding(animalID: UUID?) -> FieldCheckFindingSnapshot {
        FieldCheckFindingSnapshot(
            id: UUID(),
            recordedAt: Date(timeIntervalSince1970: 0),
            type: .generalObservation,
            severity: .info,
            status: .open,
            note: "",
            animalID: animalID,
            animalDisplayTagNumber: nil,
            animalDisplayTagColorID: nil,
            pastureName: nil,
            sessionID: UUID()
        )
    }
}
