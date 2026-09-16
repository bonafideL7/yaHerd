import Foundation
import XCTest
@testable import yaHerd

enum FieldCheckMissingFindingMutationQuickCountRollbackOperation: Equatable {
    case update
    case updateStatus
}

enum FieldCheckMissingFindingMutationQuickCountRollbackInjectedError: Error, Equatable {
    case afterMissingStateAndQuickCountNormalizationStaged(
        operation: FieldCheckMissingFindingMutationQuickCountRollbackOperation,
        sessionID: UUID,
        findingID: UUID,
        animalCheckID: UUID
    )
}

/// Permanent fault-injection hook for missing-finding mutations that can reduce quick-count
/// capacity. The final persistence runner must inject failure only after the finding mutation,
/// synchronized roster missing state, and quick-count normalization have all been staged but before
/// the logical operation commits.
@MainActor
struct FieldCheckMissingFindingMutationQuickCountRollbackFailureInjection {
    let rawQuickCowCount: (
        _ sessionID: UUID
    ) throws -> Int?
    let updateFindingFailingAfterMissingStateAndQuickCountNormalizationStaged: (
        _ sessionID: UUID,
        _ findingID: UUID,
        _ input: FieldCheckFindingInput
    ) throws -> Void
    let updateFindingStatusFailingAfterMissingStateAndQuickCountNormalizationStaged: (
        _ sessionID: UUID,
        _ findingID: UUID,
        _ status: FieldCheckFindingStatus
    ) throws -> Void
}

@MainActor
extension FieldCheckRepositoryContract {
    static func assertMissingFindingUpdateAndStatusQuickCountNormalizationFailuresRollBack(
        using fixture: FieldCheckRepositoryContractFixture,
        failureInjection: FieldCheckMissingFindingMutationQuickCountRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Finding Mutation Rollback Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let firstAnimal = try fixture.makeAnimalRepository().create(
            input: findingMutationRollbackAnimalInput(
                name: "Finding Mutation Rollback One",
                tagNumber: "FM701",
                pastureID: pasture.id
            )
        )
        _ = try fixture.makeAnimalRepository().create(
            input: findingMutationRollbackAnimalInput(
                name: "Finding Mutation Rollback Two",
                tagNumber: "FM702",
                pastureID: pasture.id
            )
        )

        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: findingMutationRollbackDate(year: 2026, month: 9, day: 27, hour: 8),
                notes: "Finding mutation quick-count rollback contract"
            )
        )
        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.cow: 2])
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: findingMutationRollbackDate(year: 2026, month: 9, day: 27, hour: 9),
                type: .generalObservation,
                severity: .info,
                status: .open,
                note: "Ordinary finding before missing transition",
                animalID: firstAnimal.id
            )
        )

        let beforeUpdateRepository = fixture.makeFieldCheckRepository()
        let beforeUpdateDetail = try XCTUnwrap(
            beforeUpdateRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let findingBeforeUpdate = try XCTUnwrap(
            beforeUpdateDetail.findings.first { $0.note == "Ordinary finding before missing transition" },
            file: file,
            line: line
        )
        let checkBeforeUpdate = try XCTUnwrap(
            beforeUpdateDetail.animalChecks.first { $0.animalID == firstAnimal.id },
            file: file,
            line: line
        )
        XCTAssertEqual(findingBeforeUpdate.type, .generalObservation, file: file, line: line)
        XCTAssertEqual(findingBeforeUpdate.status, .open, file: file, line: line)
        XCTAssertFalse(checkBeforeUpdate.isMissing, file: file, line: line)
        XCTAssertEqual(beforeUpdateDetail.quickCowCount, 2, file: file, line: line)
        XCTAssertEqual(beforeUpdateDetail.quickAnimalTypeCounts[.cow], 2, file: file, line: line)
        XCTAssertEqual(beforeUpdateDetail.missingAnimalCount, 0, file: file, line: line)
        let rawBeforeUpdateFailure = try XCTUnwrap(
            failureInjection.rawQuickCowCount(sessionID),
            "The update rollback raw-count probe must find the persisted session.",
            file: file,
            line: line
        )
        XCTAssertEqual(rawBeforeUpdateFailure, 2, file: file, line: line)
        let summaryBeforeUpdate = try XCTUnwrap(
            beforeUpdateRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        let openFindingsBeforeUpdate = try beforeUpdateRepository.fetchOpenFindings(limit: 0)

        let missingInput = FieldCheckFindingInput(
            recordedAt: findingMutationRollbackDate(year: 2026, month: 9, day: 27, hour: 10),
            type: .missingAnimal,
            severity: .critical,
            status: .open,
            note: "Staged missing transition",
            animalID: firstAnimal.id
        )

        XCTAssertThrowsError(
            try failureInjection.updateFindingFailingAfterMissingStateAndQuickCountNormalizationStaged(
                sessionID,
                findingBeforeUpdate.id,
                missingInput
            ),
            "The fault-injected finding update must fail after missing state and quick-count normalization have both been staged.",
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? FieldCheckMissingFindingMutationQuickCountRollbackInjectedError,
                .afterMissingStateAndQuickCountNormalizationStaged(
                    operation: .update,
                    sessionID: sessionID,
                    findingID: findingBeforeUpdate.id,
                    animalCheckID: checkBeforeUpdate.id
                ),
                "The update operation must surface the post-normalization sentinel rather than an unrelated earlier failure.",
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            try failureInjection.rawQuickCowCount(sessionID),
            rawBeforeUpdateFailure,
            "A failed ordinary-to-missing finding update must roll back the staged raw quick-count reduction from two cows to one.",
            file: file,
            line: line
        )
        let afterUpdateRepository = fixture.makeFieldCheckRepository()
        let afterUpdateDetail = try XCTUnwrap(
            afterUpdateRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(afterUpdateDetail.findings.first { $0.id == findingBeforeUpdate.id }, file: file, line: line),
            findingBeforeUpdate,
            "A failed ordinary-to-missing update must preserve the complete finding snapshot.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(afterUpdateDetail.animalChecks.first { $0.id == checkBeforeUpdate.id }, file: file, line: line),
            checkBeforeUpdate,
            "A failed ordinary-to-missing update must preserve the roster row and its missing state.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterUpdateDetail.quickCowCount, beforeUpdateDetail.quickCowCount, file: file, line: line)
        XCTAssertEqual(afterUpdateDetail.quickAnimalTypeCounts[.cow], beforeUpdateDetail.quickAnimalTypeCounts[.cow], file: file, line: line)
        XCTAssertEqual(afterUpdateDetail.missingAnimalCount, beforeUpdateDetail.missingAnimalCount, file: file, line: line)
        XCTAssertEqual(
            try afterUpdateRepository.fetchOpenFindings(limit: 0),
            openFindingsBeforeUpdate,
            file: file,
            line: line
        )
        let summaryAfterUpdate = try XCTUnwrap(
            afterUpdateRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summaryAfterUpdate.quickCowCount, summaryBeforeUpdate.quickCowCount, file: file, line: line)
        XCTAssertEqual(summaryAfterUpdate.quickAnimalTypeCounts[.cow], summaryBeforeUpdate.quickAnimalTypeCounts[.cow], file: file, line: line)
        XCTAssertEqual(summaryAfterUpdate.missingAnimalCount, summaryBeforeUpdate.missingAnimalCount, file: file, line: line)
        XCTAssertEqual(
            summaryAfterUpdate.animalChecks.first { $0.id == checkBeforeUpdate.id },
            summaryBeforeUpdate.animalChecks.first { $0.id == checkBeforeUpdate.id },
            file: file,
            line: line
        )

        let transitionRepository = fixture.makeFieldCheckRepository()
        try transitionRepository.updateFinding(
            sessionID: sessionID,
            findingID: findingBeforeUpdate.id,
            input: missingInput
        )
        try transitionRepository.updateFindingStatus(
            sessionID: sessionID,
            findingID: findingBeforeUpdate.id,
            status: .resolved
        )
        try transitionRepository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.cow: 2])

        let beforeStatusRepository = fixture.makeFieldCheckRepository()
        let beforeStatusDetail = try XCTUnwrap(
            beforeStatusRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let findingBeforeStatus = try XCTUnwrap(
            beforeStatusDetail.findings.first { $0.id == findingBeforeUpdate.id },
            file: file,
            line: line
        )
        let checkBeforeStatus = try XCTUnwrap(
            beforeStatusDetail.animalChecks.first { $0.id == checkBeforeUpdate.id },
            file: file,
            line: line
        )
        XCTAssertEqual(findingBeforeStatus.type, .missingAnimal, file: file, line: line)
        XCTAssertEqual(findingBeforeStatus.status, .resolved, file: file, line: line)
        XCTAssertFalse(checkBeforeStatus.isMissing, file: file, line: line)
        XCTAssertEqual(beforeStatusDetail.quickCowCount, 2, file: file, line: line)
        XCTAssertEqual(beforeStatusDetail.quickAnimalTypeCounts[.cow], 2, file: file, line: line)
        XCTAssertEqual(beforeStatusDetail.missingAnimalCount, 0, file: file, line: line)
        let rawBeforeStatusFailure = try XCTUnwrap(
            failureInjection.rawQuickCowCount(sessionID),
            "The status rollback raw-count probe must find the persisted session.",
            file: file,
            line: line
        )
        XCTAssertEqual(rawBeforeStatusFailure, 2, file: file, line: line)
        let summaryBeforeStatus = try XCTUnwrap(
            beforeStatusRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        let openFindingsBeforeStatus = try beforeStatusRepository.fetchOpenFindings(limit: 0)
        XCTAssertFalse(
            openFindingsBeforeStatus.contains { $0.id == findingBeforeStatus.id },
            "The status rollback fixture must begin with the missing finding resolved.",
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try failureInjection.updateFindingStatusFailingAfterMissingStateAndQuickCountNormalizationStaged(
                sessionID,
                findingBeforeStatus.id,
                .monitoring
            ),
            "The fault-injected status update must fail after reopened missing state and quick-count normalization have both been staged.",
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? FieldCheckMissingFindingMutationQuickCountRollbackInjectedError,
                .afterMissingStateAndQuickCountNormalizationStaged(
                    operation: .updateStatus,
                    sessionID: sessionID,
                    findingID: findingBeforeStatus.id,
                    animalCheckID: checkBeforeStatus.id
                ),
                "The status operation must surface the post-normalization sentinel rather than an unrelated earlier failure.",
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            try failureInjection.rawQuickCowCount(sessionID),
            rawBeforeStatusFailure,
            "A failed resolved-to-monitoring missing-finding status update must roll back the staged raw quick-count reduction from two cows to one.",
            file: file,
            line: line
        )
        let afterStatusRepository = fixture.makeFieldCheckRepository()
        let afterStatusDetail = try XCTUnwrap(
            afterStatusRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(afterStatusDetail.findings.first { $0.id == findingBeforeStatus.id }, file: file, line: line),
            findingBeforeStatus,
            "A failed missing-finding status reopen must preserve the complete finding snapshot.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(afterStatusDetail.animalChecks.first { $0.id == checkBeforeStatus.id }, file: file, line: line),
            checkBeforeStatus,
            "A failed missing-finding status reopen must preserve the roster row and its non-missing state.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterStatusDetail.quickCowCount, beforeStatusDetail.quickCowCount, file: file, line: line)
        XCTAssertEqual(afterStatusDetail.quickAnimalTypeCounts[.cow], beforeStatusDetail.quickAnimalTypeCounts[.cow], file: file, line: line)
        XCTAssertEqual(afterStatusDetail.missingAnimalCount, beforeStatusDetail.missingAnimalCount, file: file, line: line)
        XCTAssertEqual(
            try afterStatusRepository.fetchOpenFindings(limit: 0),
            openFindingsBeforeStatus,
            file: file,
            line: line
        )
        let summaryAfterStatus = try XCTUnwrap(
            afterStatusRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(summaryAfterStatus.quickCowCount, summaryBeforeStatus.quickCowCount, file: file, line: line)
        XCTAssertEqual(summaryAfterStatus.quickAnimalTypeCounts[.cow], summaryBeforeStatus.quickAnimalTypeCounts[.cow], file: file, line: line)
        XCTAssertEqual(summaryAfterStatus.missingAnimalCount, summaryBeforeStatus.missingAnimalCount, file: file, line: line)
        XCTAssertEqual(
            summaryAfterStatus.animalChecks.first { $0.id == checkBeforeStatus.id },
            summaryBeforeStatus.animalChecks.first { $0.id == checkBeforeStatus.id },
            file: file,
            line: line
        )
    }

    static func assertOrphanedMissingFindingStatusSynchronization(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Orphaned Missing Finding Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: findingMutationRollbackAnimalInput(
                name: "Orphaned Missing Finding Animal",
                tagNumber: "OM801",
                pastureID: pasture.id
            )
        )
        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: findingMutationRollbackDate(year: 2026, month: 9, day: 28, hour: 8),
                notes: "Orphaned missing finding synchronization contract"
            )
        )
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: findingMutationRollbackDate(year: 2026, month: 9, day: 28, hour: 9),
                type: .missingAnimal,
                severity: .warning,
                status: .open,
                note: "Missing animal before hard delete",
                animalID: animal.id
            )
        )

        let beforeDelete = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let checkBeforeDelete = try XCTUnwrap(
            beforeDelete.animalChecks.first { $0.animalID == animal.id },
            file: file,
            line: line
        )
        let findingBeforeDelete = try XCTUnwrap(
            beforeDelete.findings.first { $0.animalID == animal.id && $0.type == .missingAnimal },
            file: file,
            line: line
        )
        XCTAssertTrue(checkBeforeDelete.isMissing, file: file, line: line)
        XCTAssertEqual(beforeDelete.missingAnimalCount, 1, file: file, line: line)

        try fixture.makeAnimalRepository().delete(ids: [animal.id])
        XCTAssertNil(
            try fixture.makeAnimalRepository().fetchAnimalDetail(id: animal.id),
            "The fixture must hard-delete the live animal while retaining Field Check history.",
            file: file,
            line: line
        )

        let orphanedRepository = fixture.makeFieldCheckRepository()
        let orphanedDetail = try XCTUnwrap(
            orphanedRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let orphanedCheck = try XCTUnwrap(
            orphanedDetail.animalChecks.first { $0.id == checkBeforeDelete.id },
            "Hard deletion must retain the missing roster row by its application UUID.",
            file: file,
            line: line
        )
        let orphanedFinding = try XCTUnwrap(
            orphanedDetail.findings.first { $0.id == findingBeforeDelete.id },
            "Hard deletion must retain the unresolved missing finding by its application UUID.",
            file: file,
            line: line
        )
        XCTAssertEqual(orphanedCheck.animalID, animal.id, file: file, line: line)
        XCTAssertTrue(orphanedCheck.isMissing, file: file, line: line)
        XCTAssertEqual(orphanedDetail.missingAnimalCount, 1, file: file, line: line)
        XCTAssertEqual(orphanedFinding.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(orphanedFinding.type, .missingAnimal, file: file, line: line)
        XCTAssertEqual(orphanedFinding.status, .open, file: file, line: line)

        try orphanedRepository.updateFindingStatus(
            sessionID: sessionID,
            findingID: findingBeforeDelete.id,
            status: .resolved
        )

        let resolvedRepository = fixture.makeFieldCheckRepository()
        let resolvedDetail = try XCTUnwrap(
            resolvedRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let resolvedCheck = try XCTUnwrap(
            resolvedDetail.animalChecks.first { $0.id == checkBeforeDelete.id },
            "Resolving an orphaned missing finding must retain its historical roster row.",
            file: file,
            line: line
        )
        let resolvedFinding = try XCTUnwrap(
            resolvedDetail.findings.first { $0.id == findingBeforeDelete.id },
            "Resolving an orphaned missing finding must retain its historical finding row.",
            file: file,
            line: line
        )
        XCTAssertEqual(resolvedCheck.animalID, animal.id, file: file, line: line)
        XCTAssertFalse(
            resolvedCheck.isMissing,
            "Resolving an orphaned missing finding must clear synchronized missing state using the retained application identity rather than a live-animal relationship.",
            file: file,
            line: line
        )
        XCTAssertEqual(resolvedDetail.missingAnimalCount, 0, file: file, line: line)
        XCTAssertEqual(resolvedFinding.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(resolvedFinding.type, .missingAnimal, file: file, line: line)
        XCTAssertEqual(resolvedFinding.status, .resolved, file: file, line: line)
        XCTAssertFalse(
            try resolvedRepository.fetchOpenFindings(limit: 0).contains { $0.id == findingBeforeDelete.id },
            "The resolved orphaned missing finding must leave the open-finding projection.",
            file: file,
            line: line
        )

        let resolvedSummary = try XCTUnwrap(
            resolvedRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        let resolvedSummaryCheck = try XCTUnwrap(
            resolvedSummary.animalChecks.first { $0.id == checkBeforeDelete.id },
            file: file,
            line: line
        )
        XCTAssertFalse(resolvedSummaryCheck.isMissing, file: file, line: line)
        XCTAssertEqual(resolvedSummary.missingAnimalCount, 0, file: file, line: line)
        XCTAssertEqual(resolvedSummary.openFindingsCount, 0, file: file, line: line)
    }

    private static func findingMutationRollbackAnimalInput(
        name: String,
        tagNumber: String,
        pastureID: UUID
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: .female,
            birthDate: findingMutationRollbackDate(year: 2020, month: 1, day: 1),
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

    private static func findingMutationRollbackDate(
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
