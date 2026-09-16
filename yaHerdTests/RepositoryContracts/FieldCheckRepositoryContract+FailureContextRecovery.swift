import Foundation
import XCTest
@testable import yaHerd

/// Permanent recovery probe for the coordinated missing-finding rollback contract.
///
/// Each fault-injected operation may use its own write context. After the operation throws,
/// `saveProbeNotesThroughFailureContext` must perform the supplied probe-session notes mutation and
/// save it through the exact context that staged the failed operation. It must not call `rollback()`,
/// `reset()`, recreate the context, or otherwise discard pending changes first. Recovery belongs to
/// the production operation under test; the observable probe save deliberately flushes anything the
/// failed operation accidentally left staged.
@MainActor
struct FieldCheckMissingFindingRollbackContextRecoveryInjection {
    let rollback: FieldCheckMissingFindingRollbackFailureInjection
    let saveProbeNotesThroughFailureContext: (
        _ probeSessionID: UUID,
        _ notes: String
    ) throws -> Void
}

@MainActor
extension FieldCheckRepositoryContract {
    static func assertMissingFindingFailureContextRecovers(
        using fixture: FieldCheckRepositoryContractFixture,
        failureInjection: FieldCheckMissingFindingRollbackContextRecoveryInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Failure Context Recovery Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let sourceAnimal = try fixture.makeAnimalRepository().create(
            input: failureContextAnimalInput(
                name: "Failure Context Source",
                tagNumber: "FC501",
                pastureID: pasture.id
            )
        )
        let targetAnimal = try fixture.makeAnimalRepository().create(
            input: failureContextAnimalInput(
                name: "Failure Context Target",
                tagNumber: "FC502",
                pastureID: pasture.id
            )
        )

        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: failureContextDate(year: 2026, month: 9, day: 29, hour: 8),
                notes: "Failure-context recovery contract"
            )
        )
        let probeSessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: failureContextDate(year: 2026, month: 9, day: 29, hour: 8),
                notes: "Failure-context save probe"
            )
        )

        let initialDetail = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let sourceCheckID = try XCTUnwrap(
            initialDetail.animalChecks.first { $0.animalID == sourceAnimal.id }?.id,
            file: file,
            line: line
        )
        let targetCheckID = try XCTUnwrap(
            initialDetail.animalChecks.first { $0.animalID == targetAnimal.id }?.id,
            file: file,
            line: line
        )

        let addInput = FieldCheckFindingInput(
            recordedAt: failureContextDate(year: 2026, month: 9, day: 29, hour: 9),
            type: .missingAnimal,
            severity: .warning,
            status: .open,
            note: "Failure-context missing finding",
            animalID: sourceAnimal.id
        )

        let failedAddFindingID = try assertFailureContextSentinel(
            expectedOperation: .add,
            expectedFindingID: nil,
            file: file,
            line: line
        ) {
            try failureInjection.rollback.addMissingFindingFailingBetweenFindingAndMissingState(
                sessionID,
                addInput
            )
        }
        try assertFailureContextProbeSave(
            probeSessionID: probeSessionID,
            notes: "Probe after add failure",
            failureInjection: failureInjection,
            using: fixture,
            file: file,
            line: line
        )

        let afterAddFailure = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertFalse(
            afterAddFailure.findings.contains { $0.id == failedAddFindingID },
            "A later successful save on the failed write context must not flush the staged finding.",
            file: file,
            line: line
        )
        try assertFailureContextRosterState(
            afterAddFailure,
            sourceCheckID: sourceCheckID,
            sourceIsMissing: false,
            targetCheckID: targetCheckID,
            targetIsMissing: false,
            file: file,
            line: line
        )
        XCTAssertFalse(
            try fixture.makeFieldCheckRepository().fetchOpenFindings(limit: 0).contains {
                $0.sessionID == sessionID
            },
            "A later successful save on the failed write context must not publish the staged finding.",
            file: file,
            line: line
        )

        try repository.addFinding(sessionID: sessionID, input: addInput)
        let persistedBaseline = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let findingBeforeFailures = try XCTUnwrap(
            persistedBaseline.findings.first {
                $0.type == .missingAnimal &&
                $0.animalID == sourceAnimal.id &&
                $0.note == addInput.note
            },
            file: file,
            line: line
        )
        let findingID = findingBeforeFailures.id
        try assertFailureContextRosterState(
            persistedBaseline,
            sourceCheckID: sourceCheckID,
            sourceIsMissing: true,
            targetCheckID: targetCheckID,
            targetIsMissing: false,
            file: file,
            line: line
        )

        let reassignmentInput = FieldCheckFindingInput(
            recordedAt: failureContextDate(year: 2026, month: 9, day: 29, hour: 10),
            type: .missingAnimal,
            severity: .critical,
            status: .monitoring,
            note: "Leaked reassignment must not persist",
            animalID: targetAnimal.id
        )
        _ = try assertFailureContextSentinel(
            expectedOperation: .update,
            expectedFindingID: findingID,
            file: file,
            line: line
        ) {
            try failureInjection.rollback.updateMissingFindingFailingBetweenFindingAndMissingState(
                sessionID,
                findingID,
                reassignmentInput
            )
        }
        try assertFailureContextProbeSave(
            probeSessionID: probeSessionID,
            notes: "Probe after update failure",
            failureInjection: failureInjection,
            using: fixture,
            file: file,
            line: line
        )
        try assertFailureContextBaselineSurvivesFlush(
            sessionID: sessionID,
            expectedFinding: findingBeforeFailures,
            sourceCheckID: sourceCheckID,
            targetCheckID: targetCheckID,
            using: fixture,
            file: file,
            line: line
        )

        _ = try assertFailureContextSentinel(
            expectedOperation: .updateStatus,
            expectedFindingID: findingID,
            file: file,
            line: line
        ) {
            try failureInjection.rollback.updateMissingFindingStatusFailingBetweenFindingAndMissingState(
                sessionID,
                findingID,
                .resolved
            )
        }
        try assertFailureContextProbeSave(
            probeSessionID: probeSessionID,
            notes: "Probe after status failure",
            failureInjection: failureInjection,
            using: fixture,
            file: file,
            line: line
        )
        try assertFailureContextBaselineSurvivesFlush(
            sessionID: sessionID,
            expectedFinding: findingBeforeFailures,
            sourceCheckID: sourceCheckID,
            targetCheckID: targetCheckID,
            using: fixture,
            file: file,
            line: line
        )

        _ = try assertFailureContextSentinel(
            expectedOperation: .delete,
            expectedFindingID: findingID,
            file: file,
            line: line
        ) {
            try failureInjection.rollback.deleteMissingFindingFailingBetweenFindingAndMissingState(
                sessionID,
                findingID
            )
        }
        try assertFailureContextProbeSave(
            probeSessionID: probeSessionID,
            notes: "Probe after delete failure",
            failureInjection: failureInjection,
            using: fixture,
            file: file,
            line: line
        )
        try assertFailureContextBaselineSurvivesFlush(
            sessionID: sessionID,
            expectedFinding: findingBeforeFailures,
            sourceCheckID: sourceCheckID,
            targetCheckID: targetCheckID,
            using: fixture,
            file: file,
            line: line
        )
    }

    private static func assertFailureContextProbeSave(
        probeSessionID: UUID,
        notes: String,
        failureInjection: FieldCheckMissingFindingRollbackContextRecoveryInjection,
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString,
        line: UInt
    ) throws {
        try failureInjection.saveProbeNotesThroughFailureContext(probeSessionID, notes)
        let probeDetail = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: probeSessionID),
            "The same-context recovery probe session must remain readable after the save.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            probeDetail.notes,
            notes,
            "The recovery hook must execute an observable successful save through the context that just failed.",
            file: file,
            line: line
        )
    }

    private static func assertFailureContextSentinel(
        expectedOperation: FieldCheckMissingFindingRollbackOperation,
        expectedFindingID: UUID?,
        file: StaticString,
        line: UInt,
        operation: () throws -> Void
    ) throws -> UUID {
        var stagedFindingID: UUID?

        XCTAssertThrowsError(
            try operation(),
            "The fault-injected finding mutation must reach its coordinated-write failpoint.",
            file: file,
            line: line
        ) { error in
            guard let injected = error as? FieldCheckMissingFindingRollbackInjectedError else {
                XCTFail(
                    "The fault-injected mutation must surface FieldCheckMissingFindingRollbackInjectedError rather than an unrelated early failure: \(error)",
                    file: file,
                    line: line
                )
                return
            }
            switch injected {
            case .betweenFindingAndMissingState(let operation, let findingID):
                XCTAssertEqual(operation, expectedOperation, file: file, line: line)
                stagedFindingID = findingID
            }
        }

        let stagedFindingID = try XCTUnwrap(
            stagedFindingID,
            "The failpoint must identify the staged finding application UUID.",
            file: file,
            line: line
        )
        if let expectedFindingID {
            XCTAssertEqual(stagedFindingID, expectedFindingID, file: file, line: line)
        }
        return stagedFindingID
    }

    private static func assertFailureContextBaselineSurvivesFlush(
        sessionID: UUID,
        expectedFinding: FieldCheckFindingSnapshot,
        sourceCheckID: UUID,
        targetCheckID: UUID,
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString,
        line: UInt
    ) throws {
        let repository = fixture.makeFieldCheckRepository()
        let detail = try XCTUnwrap(
            repository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let finding = try XCTUnwrap(
            detail.findings.first { $0.id == expectedFinding.id },
            "The original finding must remain after the failed context is saved.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            finding,
            expectedFinding,
            "A later successful save on the failed context must not flush any staged finding edits.",
            file: file,
            line: line
        )
        try assertFailureContextRosterState(
            detail,
            sourceCheckID: sourceCheckID,
            sourceIsMissing: true,
            targetCheckID: targetCheckID,
            targetIsMissing: false,
            file: file,
            line: line
        )

        let openFinding = try XCTUnwrap(
            repository.fetchOpenFindings(limit: 0).first { $0.id == expectedFinding.id },
            "The original open finding must remain visible after the failed context is saved.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            openFinding,
            expectedFinding,
            "The open-finding projection must remain at its pre-failure snapshot after the recovery save.",
            file: file,
            line: line
        )

        let summary = try XCTUnwrap(
            repository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        let summarySource = try XCTUnwrap(
            summary.animalChecks.first { $0.id == sourceCheckID },
            file: file,
            line: line
        )
        let summaryTarget = try XCTUnwrap(
            summary.animalChecks.first { $0.id == targetCheckID },
            file: file,
            line: line
        )
        XCTAssertTrue(summarySource.isMissing, file: file, line: line)
        XCTAssertFalse(summaryTarget.isMissing, file: file, line: line)
        XCTAssertEqual(summary.openFindingsCount, 1, file: file, line: line)
    }

    private static func assertFailureContextRosterState(
        _ detail: FieldCheckSessionDetailSnapshot,
        sourceCheckID: UUID,
        sourceIsMissing: Bool,
        targetCheckID: UUID,
        targetIsMissing: Bool,
        file: StaticString,
        line: UInt
    ) throws {
        let sourceCheck = try XCTUnwrap(
            detail.animalChecks.first { $0.id == sourceCheckID },
            file: file,
            line: line
        )
        let targetCheck = try XCTUnwrap(
            detail.animalChecks.first { $0.id == targetCheckID },
            file: file,
            line: line
        )
        XCTAssertEqual(sourceCheck.isMissing, sourceIsMissing, file: file, line: line)
        XCTAssertEqual(targetCheck.isMissing, targetIsMissing, file: file, line: line)
    }

    private static func failureContextAnimalInput(
        name: String,
        tagNumber: String,
        pastureID: UUID
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: .female,
            birthDate: failureContextDate(year: 2020, month: 1, day: 1),
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

    private static func failureContextDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0
    ) -> Date {
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
