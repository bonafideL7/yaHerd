import Foundation
import XCTest
@testable import yaHerd

@MainActor
extension FieldCheckRepositoryContract {
    static func assertFinalMissingFindingReassignmentPreservesSourceRoster(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Final Reassignment Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let source = try fixture.makeAnimalRepository().create(
            input: reviewHardeningAnimalInput(name: "Reassignment Source", tagNumber: "FR701", pastureID: pasture.id)
        )
        let destination = try fixture.makeAnimalRepository().create(
            input: reviewHardeningAnimalInput(name: "Reassignment Destination", tagNumber: "FR702", pastureID: pasture.id)
        )
        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: reviewHardeningDate(year: 2026, month: 9, day: 27, hour: 8),
                notes: "Final finding reassignment"
            )
        )
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: reviewHardeningDate(year: 2026, month: 9, day: 27, hour: 9),
                type: .missingAnimal,
                severity: .warning,
                status: .open,
                note: "Source missing",
                animalID: source.id
            )
        )

        let before = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID), file: file, line: line)
        let findingID = try XCTUnwrap(before.findings.first { $0.animalID == source.id }?.id, file: file, line: line)
        let sourceCheckID = try XCTUnwrap(before.animalChecks.first { $0.animalID == source.id }?.id, file: file, line: line)
        let destinationCheckID = try XCTUnwrap(before.animalChecks.first { $0.animalID == destination.id }?.id, file: file, line: line)
        XCTAssertTrue(try XCTUnwrap(before.animalChecks.first { $0.id == sourceCheckID }, file: file, line: line).isMissing, file: file, line: line)

        try repository.updateFinding(
            sessionID: sessionID,
            findingID: findingID,
            input: FieldCheckFindingInput(
                recordedAt: reviewHardeningDate(year: 2026, month: 9, day: 27, hour: 10),
                type: .missingAnimal,
                severity: .critical,
                status: .monitoring,
                note: "Destination missing",
                animalID: destination.id
            )
        )

        let after = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let sourceCheck = try XCTUnwrap(
            after.animalChecks.first { $0.id == sourceCheckID },
            "Reassigning the only unresolved missing finding must preserve the source roster row and application UUID.",
            file: file,
            line: line
        )
        let destinationCheck = try XCTUnwrap(
            after.animalChecks.first { $0.id == destinationCheckID },
            file: file,
            line: line
        )
        XCTAssertEqual(sourceCheck.animalID, source.id, file: file, line: line)
        XCTAssertFalse(sourceCheck.isMissing, file: file, line: line)
        XCTAssertEqual(destinationCheck.animalID, destination.id, file: file, line: line)
        XCTAssertTrue(destinationCheck.isMissing, file: file, line: line)
        XCTAssertEqual(after.findings.first { $0.id == findingID }?.animalID, destination.id, file: file, line: line)
    }

    static func assertCompletedSessionRejectedMutationsAreMutationFree(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Completed Rejection Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: reviewHardeningAnimalInput(name: "Completed Rejection Animal", tagNumber: "CR901", pastureID: pasture.id)
        )
        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: reviewHardeningDate(year: 2026, month: 9, day: 28, hour: 8),
                notes: "Completed rejection baseline"
            )
        )
        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.cow: 1])
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: reviewHardeningDate(year: 2026, month: 9, day: 28, hour: 9),
                type: .generalObservation,
                severity: .info,
                status: .open,
                note: "Completed rejection finding",
                animalID: animal.id
            )
        )
        let openDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID), file: file, line: line)
        let animalCheckID = try XCTUnwrap(openDetail.animalChecks.first?.id, file: file, line: line)
        let findingID = try XCTUnwrap(openDetail.findings.first?.id, file: file, line: line)
        try repository.completeSession(id: sessionID)

        let completedRepository = fixture.makeFieldCheckRepository()
        let baseline = try XCTUnwrap(completedRepository.fetchSessionDetail(id: sessionID), file: file, line: line)
        let openFindingsBaseline = try completedRepository.fetchOpenFindings(limit: 0)

        XCTAssertThrowsError(try completedRepository.updateNotes(sessionID: sessionID, notes: "Blocked notes"), file: file, line: line)
        XCTAssertThrowsError(try completedRepository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.heifer: 1]), file: file, line: line)
        XCTAssertThrowsError(
            try completedRepository.setAnimalCheckCounted(sessionID: sessionID, animalCheckID: animalCheckID, isCounted: true),
            file: file,
            line: line
        )
        XCTAssertThrowsError(
            try completedRepository.setAnimalCheckMissing(sessionID: sessionID, animalCheckID: animalCheckID, isMissing: true),
            file: file,
            line: line
        )
        XCTAssertThrowsError(
            try completedRepository.addTrackedAnimalToSession(
                sessionID: sessionID,
                animalID: animal.id,
                checkedAt: reviewHardeningDate(year: 2026, month: 9, day: 28, hour: 10)
            ),
            file: file,
            line: line
        )
        XCTAssertThrowsError(
            try completedRepository.addFinding(
                sessionID: sessionID,
                input: FieldCheckFindingInput(
                    recordedAt: reviewHardeningDate(year: 2026, month: 9, day: 28, hour: 11),
                    type: .waterIssue,
                    severity: .warning,
                    status: .open,
                    note: "Blocked finding",
                    animalID: nil
                )
            ),
            file: file,
            line: line
        )
        XCTAssertThrowsError(
            try completedRepository.updateFinding(
                sessionID: sessionID,
                findingID: findingID,
                input: FieldCheckFindingInput(
                    recordedAt: reviewHardeningDate(year: 2026, month: 9, day: 28, hour: 12),
                    type: .limping,
                    severity: .critical,
                    status: .monitoring,
                    note: "Blocked update",
                    animalID: animal.id
                )
            ),
            file: file,
            line: line
        )
        XCTAssertThrowsError(try completedRepository.deleteFinding(sessionID: sessionID, findingID: findingID), file: file, line: line)

        let postRejectionRepository = fixture.makeFieldCheckRepository()
        let postRejection = try XCTUnwrap(postRejectionRepository.fetchSessionDetail(id: sessionID), file: file, line: line)
        assertReviewHardeningDetailEqual(postRejection, expected: baseline, file: file, line: line)
        XCTAssertEqual(try postRejectionRepository.fetchOpenFindings(limit: 0), openFindingsBaseline, file: file, line: line)

        try completedRepository.updateFindingStatus(sessionID: sessionID, findingID: findingID, status: .resolved)
        let afterAllowedSave = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(afterAllowedSave.completedAt, baseline.completedAt, file: file, line: line)
        XCTAssertEqual(afterAllowedSave.notes, baseline.notes, file: file, line: line)
        XCTAssertEqual(afterAllowedSave.expectedHeadCountSnapshot, baseline.expectedHeadCountSnapshot, file: file, line: line)
        XCTAssertEqual(afterAllowedSave.quickCowCount, baseline.quickCowCount, file: file, line: line)
        XCTAssertEqual(afterAllowedSave.quickHeiferCount, baseline.quickHeiferCount, file: file, line: line)
        XCTAssertEqual(afterAllowedSave.quickCalfCount, baseline.quickCalfCount, file: file, line: line)
        XCTAssertEqual(afterAllowedSave.quickBullCount, baseline.quickBullCount, file: file, line: line)
        XCTAssertEqual(afterAllowedSave.quickSteerCount, baseline.quickSteerCount, file: file, line: line)

        let baselineCheck = try XCTUnwrap(
            baseline.animalChecks.first { $0.id == animalCheckID },
            file: file,
            line: line
        )
        let afterAllowedCheck = try XCTUnwrap(
            afterAllowedSave.animalChecks.first { $0.id == animalCheckID },
            "The allowed finding-status save must preserve the completed session's roster row.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterAllowedSave.animalChecks.count, baseline.animalChecks.count, file: file, line: line)
        XCTAssertEqual(afterAllowedCheck.animalID, baselineCheck.animalID, file: file, line: line)
        XCTAssertEqual(afterAllowedCheck.displayTagNumber, baselineCheck.displayTagNumber, file: file, line: line)
        XCTAssertEqual(afterAllowedCheck.displayTagColorID, baselineCheck.displayTagColorID, file: file, line: line)
        XCTAssertEqual(afterAllowedCheck.damDisplayTagNumber, baselineCheck.damDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(afterAllowedCheck.damDisplayTagColorID, baselineCheck.damDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(afterAllowedCheck.animalName, baselineCheck.animalName, file: file, line: line)
        XCTAssertEqual(afterAllowedCheck.animalSex, baselineCheck.animalSex, file: file, line: line)
        XCTAssertEqual(afterAllowedCheck.animalType, baselineCheck.animalType, file: file, line: line)
        XCTAssertEqual(afterAllowedCheck.wasExpectedAtStart, baselineCheck.wasExpectedAtStart, file: file, line: line)
        XCTAssertEqual(afterAllowedCheck.wasCounted, baselineCheck.wasCounted, file: file, line: line)
        XCTAssertEqual(afterAllowedCheck.isMissing, baselineCheck.isMissing, file: file, line: line)
        XCTAssertTrue(baselineCheck.needsAttention, file: file, line: line)
        XCTAssertFalse(afterAllowedCheck.needsAttention, file: file, line: line)
        XCTAssertEqual(afterAllowedSave.flaggedAnimalCount, 0, file: file, line: line)

        let baselineFinding = try XCTUnwrap(baseline.findings.first { $0.id == findingID }, file: file, line: line)
        let resolvedFinding = try XCTUnwrap(afterAllowedSave.findings.first { $0.id == findingID }, file: file, line: line)
        XCTAssertEqual(resolvedFinding.recordedAt, baselineFinding.recordedAt, file: file, line: line)
        XCTAssertEqual(resolvedFinding.type, baselineFinding.type, file: file, line: line)
        XCTAssertEqual(resolvedFinding.severity, baselineFinding.severity, file: file, line: line)
        XCTAssertEqual(resolvedFinding.note, baselineFinding.note, file: file, line: line)
        XCTAssertEqual(resolvedFinding.animalID, baselineFinding.animalID, file: file, line: line)
        XCTAssertEqual(resolvedFinding.status, .resolved, file: file, line: line)
        XCTAssertEqual(afterAllowedSave.findings.count, baseline.findings.count, file: file, line: line)
    }

    private static func assertReviewHardeningDetailEqual(
        _ actual: FieldCheckSessionDetailSnapshot,
        expected: FieldCheckSessionDetailSnapshot,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.id, expected.id, file: file, line: line)
        XCTAssertEqual(actual.startedAt, expected.startedAt, file: file, line: line)
        XCTAssertEqual(actual.completedAt, expected.completedAt, file: file, line: line)
        XCTAssertEqual(actual.notes, expected.notes, file: file, line: line)
        XCTAssertEqual(actual.pastureID, expected.pastureID, file: file, line: line)
        XCTAssertEqual(actual.pastureName, expected.pastureName, file: file, line: line)
        XCTAssertEqual(actual.pastureArchivedAt, expected.pastureArchivedAt, file: file, line: line)
        XCTAssertEqual(actual.isPastureArchived, expected.isPastureArchived, file: file, line: line)
        XCTAssertEqual(actual.expectedHeadCountSnapshot, expected.expectedHeadCountSnapshot, file: file, line: line)
        XCTAssertEqual(actual.quickCowCount, expected.quickCowCount, file: file, line: line)
        XCTAssertEqual(actual.quickHeiferCount, expected.quickHeiferCount, file: file, line: line)
        XCTAssertEqual(actual.quickCalfCount, expected.quickCalfCount, file: file, line: line)
        XCTAssertEqual(actual.quickBullCount, expected.quickBullCount, file: file, line: line)
        XCTAssertEqual(actual.quickSteerCount, expected.quickSteerCount, file: file, line: line)
        XCTAssertEqual(
            actual.animalChecks.sorted(by: reviewHardeningSnapshotIDOrder),
            expected.animalChecks.sorted(by: reviewHardeningSnapshotIDOrder),
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.findings.sorted(by: reviewHardeningSnapshotIDOrder),
            expected.findings.sorted(by: reviewHardeningSnapshotIDOrder),
            file: file,
            line: line
        )
    }

    private static func reviewHardeningSnapshotIDOrder<T: Identifiable>(_ lhs: T, _ rhs: T) -> Bool where T.ID == UUID {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private static func reviewHardeningAnimalInput(name: String, tagNumber: String, pastureID: UUID) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: .female,
            birthDate: reviewHardeningDate(year: 2020, month: 1, day: 1),
            status: .active,
            pastureID: pastureID,
            sireID: nil,
            damID: nil,
            distinguishingFeatures: [],
            saleDate: nil,
            salePrice: nil,
            reasonSold: nil,
            deathDate: nil,
            causeOfDeath: nil,
            statusReferenceID: nil
        )
    }

    private static func reviewHardeningDate(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }
}
