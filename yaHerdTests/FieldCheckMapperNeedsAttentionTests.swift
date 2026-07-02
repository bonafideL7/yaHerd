import XCTest
@testable import yaHerd

final class FieldCheckMapperNeedsAttentionTests: XCTestCase {
    func testAnimalNeedsAttentionIsDerivedFromUnresolvedLinkedFindings() {
        let animalID = UUID()
        let session = makeSession()
        let animalCheck = makeAnimalCheck(animalID: animalID, tag: "101", session: session)
        let finding = makeFinding(animalID: animalID, status: .open, session: session)
        session.animalChecks = [animalCheck]
        session.findings = [finding]

        let detail = FieldCheckMapper.makeSessionDetail(from: session)

        XCTAssertEqual(detail.flaggedAnimalCount, 1)
        XCTAssertTrue(try XCTUnwrap(detail.animalChecks.first).needsAttention)
    }

    func testAnimalNeedsAttentionIsClearedWhenLinkedFindingsAreResolved() {
        let animalID = UUID()
        let session = makeSession()
        let animalCheck = makeAnimalCheck(animalID: animalID, tag: "101", session: session)
        let finding = makeFinding(animalID: animalID, status: .resolved, session: session)
        session.animalChecks = [animalCheck]
        session.findings = [finding]

        let detail = FieldCheckMapper.makeSessionDetail(from: session)

        XCTAssertEqual(detail.flaggedAnimalCount, 0)
        XCTAssertFalse(try XCTUnwrap(detail.animalChecks.first).needsAttention)
    }

    func testAnimalNeedsAttentionIgnoresFindingsLinkedToOtherAnimals() {
        let animalID = UUID()
        let session = makeSession()
        let animalCheck = makeAnimalCheck(animalID: animalID, tag: "101", session: session)
        let finding = makeFinding(animalID: UUID(), status: .open, session: session)
        session.animalChecks = [animalCheck]
        session.findings = [finding]

        let detail = FieldCheckMapper.makeSessionDetail(from: session)

        XCTAssertEqual(detail.flaggedAnimalCount, 0)
        XCTAssertFalse(try XCTUnwrap(detail.animalChecks.first).needsAttention)
    }

    private func makeSession() -> FieldCheckSession {
        FieldCheckSession(
            publicID: UUID(),
            startedAt: Date(timeIntervalSince1970: 0),
            pastureNameSnapshot: "North Pasture"
        )
    }

    private func makeAnimalCheck(
        animalID: UUID,
        tag: String,
        session: FieldCheckSession
    ) -> FieldCheckAnimalCheck {
        FieldCheckAnimalCheck(
            publicID: UUID(),
            animalIDSnapshot: animalID,
            rosterTagNumber: tag,
            animalSex: .female,
            animalType: .cow,
            session: session
        )
    }

    private func makeFinding(
        animalID: UUID,
        status: FieldCheckFindingStatus,
        session: FieldCheckSession
    ) -> FieldCheckFinding {
        FieldCheckFinding(
            publicID: UUID(),
            recordedAt: Date(timeIntervalSince1970: 10),
            type: .generalObservation,
            severity: .warning,
            status: status,
            animalIDSnapshot: animalID,
            animalDisplayTagNumberSnapshot: "101",
            pastureNameSnapshot: "North Pasture",
            sessionIDSnapshot: session.publicID,
            session: session
        )
    }
}
