import XCTest
@testable import yaHerd

final class FieldCheckAnimalAttentionRulesTests: XCTestCase {
    func testShouldNeedAttentionWhenUnresolvedFindingExistsForAnimal() {
        let animalID = UUID()
        let findings = [makeFinding(animalID: animalID)]

        XCTAssertTrue(
            FieldCheckAnimalAttentionRules.shouldNeedAttention(
                animalID: animalID,
                findings: findings
            )
        )
    }

    func testShouldNeedAttentionWhenMonitoringFindingExistsForAnimal() {
        let animalID = UUID()
        let findings = [makeFinding(animalID: animalID, status: .monitoring)]

        XCTAssertTrue(
            FieldCheckAnimalAttentionRules.shouldNeedAttention(
                animalID: animalID,
                findings: findings
            )
        )
    }

    func testShouldNotNeedAttentionWhenOnlyResolvedFindingsExistForAnimal() {
        let animalID = UUID()
        let findings = [makeFinding(animalID: animalID, status: .resolved)]

        XCTAssertFalse(
            FieldCheckAnimalAttentionRules.shouldNeedAttention(
                animalID: animalID,
                findings: findings
            )
        )
    }

    func testShouldNeedAttentionWhenResolvedAndUnresolvedFindingsExistForAnimal() {
        let animalID = UUID()
        let findings = [
            makeFinding(animalID: animalID, status: .resolved),
            makeFinding(animalID: animalID, status: .open)
        ]

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

    private func makeFinding(
        animalID: UUID?,
        status: FieldCheckFindingStatus = .open
    ) -> FieldCheckFindingSnapshot {
        FieldCheckFindingSnapshot(
            id: UUID(),
            recordedAt: Date(timeIntervalSince1970: 0),
            type: .generalObservation,
            severity: .info,
            status: status,
            note: "",
            animalID: animalID,
            animalDisplayTagNumber: nil,
            animalDisplayTagColorID: nil,
            pastureName: nil,
            sessionID: UUID()
        )
    }
}
