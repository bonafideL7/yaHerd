import Foundation
import XCTest
@testable import yaHerd

enum FieldCheckTrackedAnimalRollbackInjectedError: Error, Equatable {
    case afterMovementStaged
}

/// Permanent fault-injection hook for persistence implementations that can force the tracked-animal
/// transaction to fail after movement changes have been staged but before the logical operation commits.
///
/// The Core Data contract runner should install its failure at roster insertion or final context save so
/// the production operation surfaces `FieldCheckTrackedAnimalRollbackInjectedError.afterMovementStaged`,
/// then invoke `addTrackedAnimalToSession` through this closure. No SwiftData-specific failure adapter
/// should be added for this contract.
@MainActor
struct FieldCheckTrackedAnimalRollbackFailureInjection {
    let addTrackedAnimalFailingAfterMovementStaged: (
        _ sessionID: UUID,
        _ animalID: UUID,
        _ checkedAt: Date
    ) throws -> Void
}

@MainActor
extension FieldCheckRepositoryContract {
    static func assertTrackedAnimalInsertionFailureRollsBack(
        using fixture: FieldCheckRepositoryContractFixture,
        failureInjection: FieldCheckTrackedAnimalRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pastureRepository = fixture.makePastureRepository()
        let source = try pastureRepository.create(
            input: PastureInput(
                name: "Rollback Source",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let destination = try pastureRepository.create(
            input: PastureInput(
                name: "Rollback Destination",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )

        let animalRepository = fixture.makeAnimalRepository()
        _ = try animalRepository.create(
            input: rollbackAnimalInput(
                name: "Expected Destination Animal",
                tagNumber: "R801",
                pastureID: destination.id
            )
        )
        let tracked = try animalRepository.create(
            input: rollbackAnimalInput(
                name: "Rollback Tracked Animal",
                tagNumber: "R802",
                pastureID: source.id
            )
        )

        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: destination.id,
                startedAt: rollbackDate(year: 2026, month: 8, day: 10, hour: 8),
                notes: "Tracked-animal rollback contract"
            )
        )

        let beforeSession = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let beforeAnimal = try XCTUnwrap(
            fixture.makeAnimalRepository().fetchAnimalDetail(id: tracked.id),
            file: file,
            line: line
        )
        let beforeTimeline = try fixture.makeAnimalRepository().fetchTimeline(id: tracked.id)

        XCTAssertThrowsError(
            try failureInjection.addTrackedAnimalFailingAfterMovementStaged(
                sessionID,
                tracked.id,
                rollbackDate(year: 2026, month: 8, day: 10, hour: 9)
            ),
            "The fault-injected tracked-animal transaction must fail at the configured post-movement failpoint.",
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? FieldCheckTrackedAnimalRollbackInjectedError,
                .afterMovementStaged,
                "The production operation must reach and surface the configured post-movement failpoint rather than failing earlier for an unrelated reason.",
                file: file,
                line: line
            )
        }

        let afterSession = try XCTUnwrap(
            fixture.makeFieldCheckRepository().fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterSession,
            beforeSession,
            "A failed tracked-animal transaction must leave the Field Check session unchanged.",
            file: file,
            line: line
        )

        let afterAnimalRepository = fixture.makeAnimalRepository()
        let afterAnimal = try XCTUnwrap(
            afterAnimalRepository.fetchAnimalDetail(id: tracked.id),
            file: file,
            line: line
        )
        XCTAssertEqual(
            afterAnimal.pastureID,
            beforeAnimal.pastureID,
            "A failed tracked-animal transaction must not commit the staged pasture move.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterAnimal.pastureID, source.id, file: file, line: line)
        XCTAssertEqual(afterAnimal.pastureName, source.name, file: file, line: line)
        XCTAssertEqual(
            try afterAnimalRepository.fetchTimeline(id: tracked.id),
            beforeTimeline,
            "A failed tracked-animal transaction must not publish movement history.",
            file: file,
            line: line
        )
    }

    static func assertLinkedFindingAttentionProjections(
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let pasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "Attention North",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animal = try fixture.makeAnimalRepository().create(
            input: rollbackAnimalInput(
                name: "Attention Animal",
                tagNumber: "A901",
                pastureID: pasture.id
            )
        )

        let repository = fixture.makeFieldCheckRepository()
        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.id,
                startedAt: rollbackDate(year: 2026, month: 9, day: 10, hour: 8),
                notes: "Attention projection contract"
            )
        )
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: rollbackDate(year: 2026, month: 9, day: 10, hour: 9),
                type: .limping,
                severity: .warning,
                status: .open,
                note: "Linked attention finding",
                animalID: animal.id
            )
        )
        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: rollbackDate(year: 2026, month: 9, day: 10, hour: 10),
                type: .pinkEye,
                severity: .warning,
                status: .monitoring,
                note: "Second linked attention finding",
                animalID: animal.id
            )
        )

        let afterAddRepository = fixture.makeFieldCheckRepository()
        let afterAddDetail = try XCTUnwrap(
            afterAddRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let firstFinding = try XCTUnwrap(
            afterAddDetail.findings.first { $0.note == "Linked attention finding" },
            file: file,
            line: line
        )
        let secondFinding = try XCTUnwrap(
            afterAddDetail.findings.first { $0.note == "Second linked attention finding" },
            file: file,
            line: line
        )
        XCTAssertEqual(firstFinding.animalID, animal.id, file: file, line: line)
        XCTAssertEqual(secondFinding.animalID, animal.id, file: file, line: line)
        let detailCheck = try XCTUnwrap(
            afterAddDetail.animalChecks.first { $0.animalID == animal.id },
            file: file,
            line: line
        )
        XCTAssertTrue(
            detailCheck.needsAttention,
            "Unresolved linked findings must flag the roster animal for attention.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterAddDetail.flaggedAnimalCount, 1, file: file, line: line)

        let afterAddSummary = try XCTUnwrap(
            afterAddRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        let summaryCheck = try XCTUnwrap(
            afterAddSummary.animalChecks.first { $0.id == detailCheck.id },
            "The session summary must retain the same roster check application ID.",
            file: file,
            line: line
        )
        XCTAssertEqual(summaryCheck.animalID, animal.id, file: file, line: line)
        XCTAssertTrue(
            summaryCheck.needsAttention,
            "Session summaries must preserve linked-finding attention state.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterAddSummary.flaggedAnimalCount, 1, file: file, line: line)

        try repository.updateFindingStatus(
            sessionID: sessionID,
            findingID: firstFinding.id,
            status: .resolved
        )

        let afterFirstResolveRepository = fixture.makeFieldCheckRepository()
        let afterFirstResolveDetail = try XCTUnwrap(
            afterFirstResolveRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let afterFirstResolveCheck = try XCTUnwrap(
            afterFirstResolveDetail.animalChecks.first { $0.id == detailCheck.id },
            "Resolving one finding must not delete or omit its roster check from session detail.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterFirstResolveCheck.animalID, animal.id, file: file, line: line)
        XCTAssertTrue(
            afterFirstResolveCheck.needsAttention,
            "Resolving one of multiple linked findings must keep attention set while another remains unresolved.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterFirstResolveDetail.flaggedAnimalCount, 1, file: file, line: line)
        let afterFirstResolveOpenFindings = try afterFirstResolveRepository.fetchOpenFindings(limit: 0)
        XCTAssertFalse(afterFirstResolveOpenFindings.contains { $0.id == firstFinding.id }, file: file, line: line)
        XCTAssertTrue(afterFirstResolveOpenFindings.contains { $0.id == secondFinding.id }, file: file, line: line)

        let afterFirstResolveSummary = try XCTUnwrap(
            afterFirstResolveRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        let afterFirstResolveSummaryCheck = try XCTUnwrap(
            afterFirstResolveSummary.animalChecks.first { $0.id == detailCheck.id },
            "Resolving one finding must not delete or omit its roster check from the session summary.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterFirstResolveSummaryCheck.animalID, animal.id, file: file, line: line)
        XCTAssertTrue(
            afterFirstResolveSummaryCheck.needsAttention,
            "Session summaries must remain flagged until the final unresolved linked finding is resolved.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterFirstResolveSummary.flaggedAnimalCount, 1, file: file, line: line)

        try repository.updateFindingStatus(
            sessionID: sessionID,
            findingID: secondFinding.id,
            status: .resolved
        )

        let afterFinalResolveRepository = fixture.makeFieldCheckRepository()
        let afterFinalResolveDetail = try XCTUnwrap(
            afterFinalResolveRepository.fetchSessionDetail(id: sessionID),
            file: file,
            line: line
        )
        let resolvedDetailCheck = try XCTUnwrap(
            afterFinalResolveDetail.animalChecks.first { $0.id == detailCheck.id },
            "Resolving the final finding must not delete or omit its roster check from session detail.",
            file: file,
            line: line
        )
        XCTAssertEqual(resolvedDetailCheck.animalID, animal.id, file: file, line: line)
        XCTAssertFalse(
            resolvedDetailCheck.needsAttention,
            "Resolving the animal's final unresolved linked finding must clear attention state.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterFinalResolveDetail.flaggedAnimalCount, 0, file: file, line: line)

        let afterFinalResolveSummary = try XCTUnwrap(
            afterFinalResolveRepository.fetchSessions().first { $0.id == sessionID },
            file: file,
            line: line
        )
        let resolvedSummaryCheck = try XCTUnwrap(
            afterFinalResolveSummary.animalChecks.first { $0.id == detailCheck.id },
            "Resolving the final finding must not delete or omit its roster check from the session summary.",
            file: file,
            line: line
        )
        XCTAssertEqual(resolvedSummaryCheck.animalID, animal.id, file: file, line: line)
        XCTAssertFalse(
            resolvedSummaryCheck.needsAttention,
            "No resolved linked findings may keep the session summary flagged once the final unresolved finding is resolved.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterFinalResolveSummary.flaggedAnimalCount, 0, file: file, line: line)
    }

    private static func rollbackAnimalInput(
        name: String,
        tagNumber: String,
        pastureID: UUID
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: .female,
            birthDate: rollbackDate(year: 2020, month: 1, day: 1),
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

    private static func rollbackDate(
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