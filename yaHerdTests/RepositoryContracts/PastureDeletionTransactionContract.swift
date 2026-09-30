import Foundation
import XCTest
@testable import yaHerd

/// Target-runner probe for one representative successful normalized Pasture deletion plan.
///
/// The fixture must prepare at least two target Pastures, resident Animals including at least one dam
/// with visible maternal offspring, one target Pasture assigned to a group that retains a non-deleted
/// member, a distinct affected group whose final member Pasture is deleted, Field Check history for at
/// least one target Pasture, and unrelated control records. The writer must be the real
/// `PastureDeletionTransactionWriting` implementation.
///
/// The plan must follow the Domain-authored operation order documented by
/// `TRANSACTION_BOUNDARIES.md`: resident moves first, one Field Check archive operation second, and
/// one final Pasture delete operation last.
@MainActor
struct PastureDeletionTransactionContractProbe {
    let writer: any PastureDeletionTransactionWriting
    let plan: DeletePasturesTransactionPlan
    let makePastureRepository: () -> any PastureRepository
    let makeAnimalRepository: () -> any AnimalRepository
    let makeFieldCheckRepository: () -> any FieldCheckRepository
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    /// Target-runner instrumentation of operations actually executed by the transaction writer.
    /// Fixture setup must leave this empty; after success it must equal `plan.operations` exactly.
    let executedOperations: () -> [PastureDeletionOperation]
    let unaffectedPastureID: UUID
    let unaffectedAnimalID: UUID
    let unaffectedFieldCheckSessionID: UUID
}

/// Permanent persistence-neutral success contract for the final atomic Pasture deletion port.
///
/// User-facing workflow policy and broader historical scenarios remain owned by
/// `PastureDeletionWorkflowContract`. Stale expected-state rejection is owned by
/// `PersistenceTransactionPreconditionContract`; partial-write rollback/recovery is owned by
/// `PersistenceTransactionRollbackContract`; mutation publication is owned by
/// `MutationBoundaryContract`.
@MainActor
enum PastureDeletionTransactionContract {
    private struct MoveExpectation {
        let animalID: UUID
        let fromPastureID: UUID
        let toPastureID: UUID?
    }

    static func assertSuccessfulPlanExecutesExactlyAsAuthored(
        using probe: PastureDeletionTransactionContractProbe,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let parsed = try parseAndValidateRepresentativePlan(probe.plan, file: file, line: line)

        let animalRepository = probe.makeAnimalRepository()
        let pastureRepository = probe.makePastureRepository()
        let fieldCheckRepository = probe.makeFieldCheckRepository()
        let dashboardBefore = try await probe.makeDashboardQueryReader().fetchDashboardRecords()
        XCTAssertTrue(
            probe.executedOperations().isEmpty,
            "Target-runner operation instrumentation must begin empty before transaction execution.",
            file: file,
            line: line
        )

        var beforeAnimals: [UUID: AnimalDetailSnapshot] = [:]
        var beforeMovementTimelines: [UUID: [AnimalTimelineEvent]] = [:]
        var beforeDashboardAnimals: [UUID: DashboardAnimalRecord] = [:]
        for move in parsed.moves {
            let before = try XCTUnwrap(
                animalRepository.fetchAnimalDetail(id: move.animalID),
                "Every move operation must reference an existing Animal in the representative fixture.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                before.pastureID,
                move.fromPastureID,
                "The representative plan must begin with each moved Animal in its authored source Pasture.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                before.status,
                .active,
                "Domain-authored Pasture deletion residents must be active Animals.",
                file: file,
                line: line
            )
            XCTAssertFalse(
                before.isArchived,
                "Domain-authored Pasture deletion residents must be unarchived Animals.",
                file: file,
                line: line
            )
            beforeAnimals[move.animalID] = before
            beforeMovementTimelines[move.animalID] = try animalRepository.fetchTimeline(id: move.animalID)
            beforeDashboardAnimals[move.animalID] = try XCTUnwrap(
                dashboardBefore.animals.first { $0.id == move.animalID },
                "Every moved Animal must be visible through Dashboard records before deletion.",
                file: file,
                line: line
            )
        }

        XCTAssertTrue(
            beforeAnimals.values.contains {
                $0.maternalOffspringCountIncludingArchived > 0
                    && !$0.maternalOffspring.isEmpty
            },
            "The representative Pasture deletion plan must move at least one dam with visible offspring so inverse offspring preservation is observable.",
            file: file,
            line: line
        )

        var affectedGroupsBefore: [UUID: PastureGroupDetailSnapshot] = [:]
        var deletedGroupedPastureIDsByGroup: [UUID: Set<UUID>] = [:]

        for expectedState in probe.plan.expectedStates {
            let targetPasture = try XCTUnwrap(
                pastureRepository.fetchPastureDetail(id: expectedState.pastureID),
                "Every deletion target must exist before the transaction executes.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                Set(try pastureRepository.fetchResidentAnimals(pastureID: expectedState.pastureID).map(\.id)),
                expectedState.residentAnimalIDs,
                "The representative success probe must begin with resident state exactly matching the Domain-authored expected state.",
                file: file,
                line: line
            )

            if let groupID = targetPasture.groupID {
                let groupBefore = try XCTUnwrap(
                    pastureRepository.fetchPastureGroupDetail(id: groupID),
                    "A grouped deletion target must resolve its PastureGroup before transaction execution.",
                    file: file,
                    line: line
                )
                XCTAssertTrue(
                    groupBefore.pastures.contains { $0.id == targetPasture.id },
                    "The grouped target Pasture must be present in its pre-delete group detail projection.",
                    file: file,
                    line: line
                )
                if let existing = affectedGroupsBefore[groupID] {
                    XCTAssertEqual(
                        existing,
                        groupBefore,
                        "Repeated targets from the same group must observe one stable pre-delete group projection.",
                        file: file,
                        line: line
                    )
                } else {
                    affectedGroupsBefore[groupID] = groupBefore
                }
                deletedGroupedPastureIDsByGroup[groupID, default: []].insert(targetPasture.id)
            }
        }

        XCTAssertTrue(
            affectedGroupsBefore.contains { groupID, groupBefore in
                let deletedMembers = deletedGroupedPastureIDsByGroup[groupID, default: []]
                return groupBefore.pastures.contains { !deletedMembers.contains($0.id) }
            },
            "The representative deletion plan must remove at least one grouped Pasture while leaving another member in that same group.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            affectedGroupsBefore.contains { groupID, groupBefore in
                let memberIDs = Set(groupBefore.pastures.map(\.id))
                let deletedMembers = deletedGroupedPastureIDsByGroup[groupID, default: []]
                return !memberIDs.isEmpty && memberIDs.isSubset(of: deletedMembers)
            },
            "The representative deletion plan must also delete the final member of a distinct PastureGroup so empty-group survival is observable.",
            file: file,
            line: line
        )

        var destinationResidentsBefore: [UUID: Set<UUID>] = [:]
        for destinationPastureID in Set(parsed.moves.compactMap(\.toPastureID)) {
            XCTAssertFalse(
                parsed.deletedPastureIDs.contains(destinationPastureID),
                "A resident move destination must not also be deleted by the same normalized plan.",
                file: file,
                line: line
            )
            XCTAssertNotNil(
                try pastureRepository.fetchPastureDetail(id: destinationPastureID),
                "Every non-nil resident move destination must exist before the transaction executes.",
                file: file,
                line: line
            )
            destinationResidentsBefore[destinationPastureID] = Set(
                try pastureRepository.fetchResidentAnimals(pastureID: destinationPastureID).map(\.id)
            )
        }

        let targetSessionSummaries = try fieldCheckRepository.fetchSessions().filter {
            guard let pastureID = $0.pastureID else { return false }
            return parsed.archivedPastureIDs.contains(pastureID)
        }
        XCTAssertFalse(
            targetSessionSummaries.isEmpty,
            "The representative target-port fixture must include Field Check history for a deleted Pasture.",
            file: file,
            line: line
        )

        var beforeTargetSessions: [UUID: FieldCheckSessionDetailSnapshot] = [:]
        for summary in targetSessionSummaries {
            beforeTargetSessions[summary.id] = try XCTUnwrap(
                fieldCheckRepository.fetchSessionDetail(id: summary.id),
                file: file,
                line: line
            )
        }

        let unaffectedPastureBefore = try XCTUnwrap(
            pastureRepository.fetchPastureDetail(id: probe.unaffectedPastureID),
            file: file,
            line: line
        )
        let unaffectedAnimalBefore = try XCTUnwrap(
            animalRepository.fetchAnimalDetail(id: probe.unaffectedAnimalID),
            file: file,
            line: line
        )
        let unaffectedSessionBefore = try XCTUnwrap(
            fieldCheckRepository.fetchSessionDetail(id: probe.unaffectedFieldCheckSessionID),
            file: file,
            line: line
        )
        let unaffectedDashboardAnimalBefore = try XCTUnwrap(
            dashboardBefore.animals.first { $0.id == probe.unaffectedAnimalID },
            file: file,
            line: line
        )
        let unaffectedDashboardPastureBefore = try XCTUnwrap(
            dashboardBefore.pastures.first { $0.id == probe.unaffectedPastureID },
            file: file,
            line: line
        )
        XCTAssertFalse(
            parsed.deletedPastureIDs.contains(probe.unaffectedPastureID),
            "The unrelated Pasture control must not be a deletion target.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            parsed.moves.contains { $0.toPastureID == probe.unaffectedPastureID },
            "The unrelated Pasture control must not be a move destination whose resident count is expected to change.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            parsed.moves.contains { $0.animalID == probe.unaffectedAnimalID },
            "The unrelated Animal control must not be included in a move operation.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            beforeTargetSessions.keys.contains(probe.unaffectedFieldCheckSessionID),
            "The unrelated Field Check control must not belong to a Pasture being archived.",
            file: file,
            line: line
        )

        try probe.writer.deletePastures(probe.plan)
        XCTAssertEqual(
            probe.executedOperations(),
            probe.plan.operations,
            "The persistence transaction must execute the Domain-authored operation sequence exactly as supplied.",
            file: file,
            line: line
        )

        let dashboardReaderAfter = probe.makeDashboardQueryReader()
        let dashboardAfter = try await dashboardReaderAfter.fetchDashboardRecords()
        let dashboardPasturesAfter = try await dashboardReaderAfter.fetchDashboardPastureRecords()
        let dashboardActiveAnimalsAfter = try await dashboardReaderAfter.fetchDashboardAnimalRecords(kind: .active)
        let dashboardWorkingPenAnimalsAfter = try await dashboardReaderAfter.fetchDashboardAnimalRecords(kind: .workingPen)
        let dashboardUnassignedAnimalsAfter = try await dashboardReaderAfter.fetchDashboardAnimalRecords(kind: .unassigned)
        let backgroundPastureOptionsAfter = try await probe.makeAnimalListQueryReader()
            .fetchAnimalPastureOptions(limit: ReadPageRequest.maximumLimit)

        let reloadedAnimals = probe.makeAnimalRepository()
        for move in parsed.moves {
            let after = try XCTUnwrap(
                reloadedAnimals.fetchAnimalDetail(id: move.animalID),
                "Pasture deletion must move residents rather than delete them.",
                file: file,
                line: line
            )
            XCTAssertEqual(after.pastureID, move.toPastureID, file: file, line: line)
            let afterTimeline = try reloadedAnimals.fetchTimeline(id: move.animalID)
            let beforeTimeline = beforeMovementTimelines[move.animalID, default: []]
            XCTAssertEqual(
                movementCount(afterTimeline),
                movementCount(beforeTimeline) + 1,
                "Each authored resident move must append exactly one durable movement-history event.",
                file: file,
                line: line
            )
            let before = try XCTUnwrap(beforeAnimals[move.animalID], file: file, line: line)
            assertExactlyOneMovementEventAdded(
                before: beforeTimeline,
                after: afterTimeline,
                expectedDetails: "\(before.pastureName ?? "—") → \(after.pastureName ?? "—")",
                file: file,
                line: line
            )
            XCTAssertEqual(
                multisetCounts(preservedTimelineSignatures(afterTimeline)),
                multisetCounts(preservedTimelineSignatures(beforeTimeline)),
                "Pasture deletion movement must preserve every non-movement timeline entry except the Animal's derived primary Birth projection.",
                file: file,
                line: line
            )
            try assertPrimaryBirthProjectionMatchesCurrentRelationships(
                detail: after,
                timeline: afterTimeline,
                repository: reloadedAnimals,
                file: file,
                line: line
            )
            assertMovedAnimalPreservesNonPastureState(after, before: before, file: file, line: line)

            let dashboardBeforeRecord = try XCTUnwrap(
                beforeDashboardAnimals[move.animalID],
                file: file,
                line: line
            )
            let dashboardAfterRecord = try XCTUnwrap(
                dashboardAfter.animals.first { $0.id == move.animalID },
                "Every moved Animal must remain visible through Dashboard records after Pasture deletion.",
                file: file,
                line: line
            )
            assertDashboardMovePreservesNonPastureState(
                dashboardAfterRecord,
                before: dashboardBeforeRecord,
                file: file,
                line: line
            )
            XCTAssertEqual(dashboardAfterRecord.pastureID, after.pastureID, file: file, line: line)
            XCTAssertEqual(dashboardAfterRecord.pastureName, after.pastureName, file: file, line: line)
            XCTAssertEqual(dashboardAfterRecord.location, after.location, file: file, line: line)

            let activeRecord = try XCTUnwrap(
                dashboardActiveAnimalsAfter.first { $0.id == move.animalID },
                "Every moved resident must remain visible in the Dashboard active-Animal projection.",
                file: file,
                line: line
            )
            assertDashboardRecordsSemanticallyEqual(
                activeRecord,
                dashboardAfterRecord,
                file: file,
                line: line
            )
            XCTAssertNil(
                dashboardWorkingPenAnimalsAfter.first { $0.id == move.animalID },
                "Pasture deletion movement must not place a resident in the Dashboard Working-pen projection.",
                file: file,
                line: line
            )
            if move.toPastureID == nil {
                let unassignedRecord = try XCTUnwrap(
                    dashboardUnassignedAnimalsAfter.first { $0.id == move.animalID },
                    "A resident moved to no destination Pasture must appear in the Dashboard unassigned projection.",
                    file: file,
                    line: line
                )
                assertDashboardRecordsSemanticallyEqual(
                    unassignedRecord,
                    dashboardAfterRecord,
                    file: file,
                    line: line
                )
            } else {
                XCTAssertNil(
                    dashboardUnassignedAnimalsAfter.first { $0.id == move.animalID },
                    "A resident moved to a concrete destination Pasture must not remain in the Dashboard unassigned projection.",
                    file: file,
                    line: line
                )
            }
        }

        let reloadedPastures = probe.makePastureRepository()
        let pastureSummariesAfter = try reloadedPastures.fetchPastures()
        let pastureOptionsAfter = try reloadedPastures.fetchPastureOptions()
        let groupSummariesAfter = try reloadedPastures.fetchPastureGroups()
        for (groupID, groupBefore) in affectedGroupsBefore {
            let deletedMembers = deletedGroupedPastureIDsByGroup[groupID, default: []]
            let expectedMemberIDs = Set(groupBefore.pastures.map(\.id)).subtracting(deletedMembers)

            let groupAfter = try XCTUnwrap(
                reloadedPastures.fetchPastureGroupDetail(id: groupID),
                "Deleting grouped Pastures must preserve the containing PastureGroup.",
                file: file,
                line: line
            )
            XCTAssertEqual(groupAfter.id, groupBefore.id, file: file, line: line)
            XCTAssertEqual(groupAfter.name, groupBefore.name, file: file, line: line)
            XCTAssertEqual(groupAfter.grazeDays, groupBefore.grazeDays, file: file, line: line)
            XCTAssertEqual(groupAfter.restDays, groupBefore.restDays, file: file, line: line)
            XCTAssertEqual(
                Set(groupAfter.pastures.map(\.id)),
                expectedMemberIDs,
                "Pasture deletion must remove only deleted members from the surviving group detail projection.",
                file: file,
                line: line
            )

            let summaryAfter = try XCTUnwrap(
                groupSummariesAfter.first { $0.id == groupID },
                "A surviving PastureGroup must remain visible in the group-list projection after member deletion.",
                file: file,
                line: line
            )
            XCTAssertEqual(summaryAfter.name, groupBefore.name, file: file, line: line)
            XCTAssertEqual(summaryAfter.grazeDays, groupBefore.grazeDays, file: file, line: line)
            XCTAssertEqual(summaryAfter.restDays, groupBefore.restDays, file: file, line: line)
            XCTAssertEqual(
                summaryAfter.pastureCount,
                expectedMemberIDs.count,
                "PastureGroup list count must reflect deletion of grouped member Pastures.",
                file: file,
                line: line
            )
        }

        for (destinationPastureID, residentsBefore) in destinationResidentsBefore {
            let movedToDestination = Set(
                parsed.moves
                    .filter { $0.toPastureID == destinationPastureID }
                    .map(\.animalID)
            )
            let destinationResidentsAfter = Set(
                try reloadedPastures
                    .fetchResidentAnimals(pastureID: destinationPastureID)
                    .map(\.id)
            )
            XCTAssertEqual(
                destinationResidentsAfter,
                residentsBefore.union(movedToDestination),
                "The destination Pasture resident projection must preserve prior residents and add every authored moved Animal exactly once.",
                file: file,
                line: line
            )
            try assertSurvivingPastureCountProjections(
                pastureID: destinationPastureID,
                expectedResidentCount: destinationResidentsAfter.count,
                pastureRepository: reloadedPastures,
                dashboardRecords: dashboardAfter,
                dashboardPastures: dashboardPasturesAfter,
                file: file,
                line: line
            )
            let destinationDetail = try XCTUnwrap(
                reloadedPastures.fetchPastureDetail(id: destinationPastureID),
                file: file,
                line: line
            )
            XCTAssertEqual(
                try XCTUnwrap(
                    pastureOptionsAfter.first { $0.id == destinationPastureID },
                    "A surviving move destination must remain selectable through synchronous Pasture reference options.",
                    file: file,
                    line: line
                ).name,
                destinationDetail.name,
                file: file,
                line: line
            )
            XCTAssertEqual(
                try XCTUnwrap(
                    backgroundPastureOptionsAfter.first { $0.id == destinationPastureID },
                    "A surviving move destination must remain selectable through the production background Animal-list Pasture options.",
                    file: file,
                    line: line
                ).name,
                destinationDetail.name,
                file: file,
                line: line
            )
        }

        for pastureID in parsed.deletedPastureIDs {
            XCTAssertNil(
                try reloadedPastures.fetchPastureDetail(id: pastureID),
                "Every Pasture in the final delete operation must be absent after commit.",
                file: file,
                line: line
            )
            XCTAssertFalse(
                pastureSummariesAfter.contains { $0.id == pastureID },
                "Deleted Pastures must disappear from the Pasture list projection after commit.",
                file: file,
                line: line
            )
            XCTAssertFalse(
                pastureOptionsAfter.contains { $0.id == pastureID },
                "Deleted Pastures must disappear from synchronous Pasture reference options after commit.",
                file: file,
                line: line
            )
            XCTAssertFalse(
                backgroundPastureOptionsAfter.contains { $0.id == pastureID },
                "Deleted Pastures must disappear from production background Animal-list Pasture options after commit.",
                file: file,
                line: line
            )
            XCTAssertFalse(
                dashboardAfter.pastures.contains { $0.id == pastureID },
                "Deleted Pastures must disappear from Dashboard records after commit.",
                file: file,
                line: line
            )
            XCTAssertFalse(
                dashboardPasturesAfter.contains { $0.id == pastureID },
                "Deleted Pastures must disappear from the Dashboard Pasture-list projection after commit.",
                file: file,
                line: line
            )
        }

        let reloadedFieldChecks = probe.makeFieldCheckRepository()
        let reloadedSummaries = try reloadedFieldChecks.fetchSessions()
        for (sessionID, before) in beforeTargetSessions {
            let after = try XCTUnwrap(
                reloadedFieldChecks.fetchSessionDetail(id: sessionID),
                "Field Check history for a deleted Pasture must remain readable.",
                file: file,
                line: line
            )
            assertArchivedSession(
                after,
                preserves: before,
                archivedAt: parsed.archivedAt,
                file: file,
                line: line
            )

            let summary = try XCTUnwrap(
                reloadedSummaries.first { $0.id == sessionID },
                "Archived Field Check history must remain visible through the session-list projection.",
                file: file,
                line: line
            )
            XCTAssertTrue(summary.isPastureArchived, file: file, line: line)
            XCTAssertEqual(summary.pastureArchivedAt, parsed.archivedAt, file: file, line: line)
            XCTAssertEqual(summary.pastureID, before.pastureID, file: file, line: line)
            XCTAssertEqual(summary.pastureName, before.pastureName, file: file, line: line)
            XCTAssertEqual(Set(summary.animalChecks), Set(before.animalChecks), file: file, line: line)
        }

        XCTAssertEqual(
            try XCTUnwrap(
                reloadedPastures.fetchPastureDetail(id: probe.unaffectedPastureID),
                file: file,
                line: line
            ),
            unaffectedPastureBefore,
            "Atomic Pasture deletion must not mutate an unrelated Pasture.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(
                pastureOptionsAfter.first { $0.id == probe.unaffectedPastureID },
                file: file,
                line: line
            ).name,
            unaffectedPastureBefore.name,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(
                backgroundPastureOptionsAfter.first { $0.id == probe.unaffectedPastureID },
                file: file,
                line: line
            ).name,
            unaffectedPastureBefore.name,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(
                reloadedAnimals.fetchAnimalDetail(id: probe.unaffectedAnimalID),
                file: file,
                line: line
            ),
            unaffectedAnimalBefore,
            "Atomic Pasture deletion must not mutate an unrelated Animal.",
            file: file,
            line: line
        )
        assertDashboardRecordsSemanticallyEqual(
            try XCTUnwrap(
                dashboardAfter.animals.first { $0.id == probe.unaffectedAnimalID },
                file: file,
                line: line
            ),
            unaffectedDashboardAnimalBefore,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(
                dashboardAfter.pastures.first { $0.id == probe.unaffectedPastureID },
                file: file,
                line: line
            ),
            unaffectedDashboardPastureBefore,
            "Atomic Pasture deletion must not alter the unrelated Pasture in Dashboard records.",
            file: file,
            line: line
        )
        assertSessionUnchanged(
            try XCTUnwrap(
                reloadedFieldChecks.fetchSessionDetail(id: probe.unaffectedFieldCheckSessionID),
                file: file,
                line: line
            ),
            expected: unaffectedSessionBefore,
            message: "Atomic Pasture deletion must not mutate an unrelated Field Check session.",
            file: file,
            line: line
        )
    }

    private struct ParsedPlan {
        let moves: [MoveExpectation]
        let archivedPastureIDs: Set<UUID>
        let archivedAt: Date
        let deletedPastureIDs: Set<UUID>
    }

    private static func parseAndValidateRepresentativePlan(
        _ plan: DeletePasturesTransactionPlan,
        file: StaticString,
        line: UInt
    ) throws -> ParsedPlan {
        XCTAssertGreaterThanOrEqual(
            plan.expectedStates.count,
            2,
            "The representative transaction contract must exercise batch deletion of at least two Pastures.",
            file: file,
            line: line
        )

        var moves: [MoveExpectation] = []
        var archivePastureIDs: [UUID]?
        var archivedAt: Date?
        var deletedPastureIDs: [UUID]?
        var phase = 0

        for operation in plan.operations {
            switch operation {
            case .moveAnimals(let animalIDs, let fromPastureID, let toPastureID):
                XCTAssertEqual(
                    phase,
                    0,
                    "All authored move operations must precede archive/delete operations.",
                    file: file,
                    line: line
                )
                XCTAssertFalse(animalIDs.isEmpty, file: file, line: line)
                moves.append(
                    contentsOf: animalIDs.map {
                        MoveExpectation(
                            animalID: $0,
                            fromPastureID: fromPastureID,
                            toPastureID: toPastureID
                        )
                    }
                )

            case .archiveFieldChecks(let pastureIDs, let operationArchivedAt):
                XCTAssertEqual(
                    phase,
                    0,
                    "The representative plan must contain one archive operation after all moves and before deletion.",
                    file: file,
                    line: line
                )
                XCTAssertNil(archivePastureIDs, "Only one archive operation is expected in the normalized representative plan.", file: file, line: line)
                archivePastureIDs = pastureIDs
                archivedAt = operationArchivedAt
                phase = 1

            case .deletePastures(let ids):
                XCTAssertEqual(
                    phase,
                    1,
                    "The final Pasture delete operation must follow the Field Check archive operation.",
                    file: file,
                    line: line
                )
                XCTAssertNil(deletedPastureIDs, "Only one final delete operation is expected in the normalized representative plan.", file: file, line: line)
                deletedPastureIDs = ids
                phase = 2
            }
        }

        let archiveIDList = try XCTUnwrap(archivePastureIDs, file: file, line: line)
        let deleteIDList = try XCTUnwrap(deletedPastureIDs, file: file, line: line)
        let archiveIDs = Set(archiveIDList)
        let archiveDate = try XCTUnwrap(archivedAt, file: file, line: line)
        let deleteIDs = Set(deleteIDList)
        let expectedIDs = Set(plan.expectedStates.map(\.pastureID))

        XCTAssertEqual(expectedIDs.count, plan.expectedStates.count, "Expected-state Pasture IDs must be unique.", file: file, line: line)
        XCTAssertEqual(archiveIDs.count, archiveIDList.count, "Archive-operation Pasture IDs must be unique.", file: file, line: line)
        XCTAssertEqual(deleteIDs.count, deleteIDList.count, "Delete-operation Pasture IDs must be unique.", file: file, line: line)
        XCTAssertEqual(phase, 2, "The normalized representative plan must end with deletion.", file: file, line: line)
        XCTAssertFalse(moves.isEmpty, "The representative plan must exercise resident movement.", file: file, line: line)
        XCTAssertEqual(archiveIDs, deleteIDs, "Field Check archival must target the same Pastures being deleted.", file: file, line: line)
        XCTAssertEqual(deleteIDs, expectedIDs, "Expected-state revalidation must cover every and only deleted Pasture.", file: file, line: line)
        XCTAssertTrue(
            Set(moves.map(\.fromPastureID)).isSubset(of: deleteIDs),
            "Resident moves in the normalized plan must originate from Pastures being deleted.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            Set(moves.compactMap(\.toPastureID)).isDisjoint(with: deleteIDs),
            "Resident move destinations must not also be deletion targets in the same normalized plan.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(moves.map(\.animalID)).count,
            moves.count,
            "A representative normalized plan must not move the same Animal more than once.",
            file: file,
            line: line
        )

        let expectedStateGroups = Dictionary(
            grouping: plan.expectedStates,
            by: \.pastureID
        )
        let expectedResidentsByPastureID = expectedStateGroups.compactMapValues {
            $0.first?.residentAnimalIDs
        }
        let movedResidentsByPastureID = Dictionary(
            grouping: moves,
            by: \.fromPastureID
        ).mapValues { Set($0.map(\.animalID)) }

        for pastureID in expectedIDs {
            XCTAssertEqual(
                movedResidentsByPastureID[pastureID, default: []],
                expectedResidentsByPastureID[pastureID, default: []],
                "The representative normalized plan must author exactly one move for every expected resident before deleting its Pasture.",
                file: file,
                line: line
            )
        }

        return ParsedPlan(
            moves: moves,
            archivedPastureIDs: archiveIDs,
            archivedAt: archiveDate,
            deletedPastureIDs: deleteIDs
        )
    }

    private enum PreservedTimelineKind: Hashable {
        case birthHistory
        case health
        case pregnancy
        case status
        case tag
    }

    private struct PreservedTimelineSignature: Hashable {
        let kind: PreservedTimelineKind
        let date: Date
        let title: String
        let details: String?
    }

    private struct MovementTimelineSignature: Hashable {
        let date: Date
        let title: String
        let details: String?
    }

    private static func preservedTimelineSignatures(
        _ events: [AnimalTimelineEvent]
    ) -> [PreservedTimelineSignature] {
        events.compactMap { event in
            let kind: PreservedTimelineKind
            switch event.type {
            case .birth:
                guard event.title != "Birth" else { return nil }
                kind = .birthHistory
            case .health:
                kind = .health
            case .pregnancy:
                kind = .pregnancy
            case .status:
                kind = .status
            case .tag:
                kind = .tag
            case .movement:
                return nil
            }
            return PreservedTimelineSignature(
                kind: kind,
                date: event.date,
                title: event.title,
                details: event.details
            )
        }
    }

    private static func assertPrimaryBirthProjectionMatchesCurrentRelationships(
        detail: AnimalDetailSnapshot,
        timeline: [AnimalTimelineEvent],
        repository: any AnimalRepository,
        file: StaticString,
        line: UInt
    ) throws {
        let primaryBirthEvents = timeline.filter { event in
            guard case .birth = event.type else { return false }
            return event.title == "Birth"
        }
        XCTAssertEqual(
            primaryBirthEvents.count,
            1,
            "Each moved Animal must expose exactly one derived primary Birth projection.",
            file: file,
            line: line
        )
        guard let birth = primaryBirthEvents.first else { return }

        XCTAssertEqual(birth.date, detail.birthDate, file: file, line: line)

        var components: [String] = []
        if let damID = detail.damID,
           let dam = try repository.fetchAnimalDetail(id: damID) {
            let display = dam.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                components.append("Dam: \(display)")
            }
        }
        if let sireID = detail.sireID,
           let sire = try repository.fetchAnimalDetail(id: sireID) {
            let display = sire.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                components.append("Sire: \(display)")
            }
        }
        if let pastureName = detail.pastureName, !pastureName.isEmpty {
            components.append("Pasture: \(pastureName)")
        }

        XCTAssertEqual(
            birth.details,
            components.isEmpty ? nil : components.joined(separator: " • "),
            "The derived primary Birth projection must reflect the Animal's post-move parent tags and current Pasture.",
            file: file,
            line: line
        )
    }

    private static func movementSignatures(
        _ events: [AnimalTimelineEvent]
    ) -> [MovementTimelineSignature] {
        events.compactMap { event in
            guard case .movement = event.type else { return nil }
            return MovementTimelineSignature(
                date: event.date,
                title: event.title,
                details: event.details
            )
        }
    }

    private static func movementCount(_ events: [AnimalTimelineEvent]) -> Int {
        movementSignatures(events).count
    }

    private static func assertExactlyOneMovementEventAdded(
        before: [AnimalTimelineEvent],
        after: [AnimalTimelineEvent],
        expectedDetails: String,
        file: StaticString,
        line: UInt
    ) {
        let beforeCounts = multisetCounts(movementSignatures(before))
        let afterCounts = multisetCounts(movementSignatures(after))
        var added: [MovementTimelineSignature] = []
        var removedCount = 0

        for signature in Set(beforeCounts.keys).union(afterCounts.keys) {
            let delta = afterCounts[signature, default: 0] - beforeCounts[signature, default: 0]
            if delta > 0 {
                added.append(contentsOf: repeatElement(signature, count: delta))
            } else if delta < 0 {
                removedCount += -delta
            }
        }

        XCTAssertEqual(
            removedCount,
            0,
            "Pasture deletion movement history must not remove or rewrite existing movement events.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            added.count,
            1,
            "Each authored resident move must append exactly one new movement-history event.",
            file: file,
            line: line
        )
        guard let appended = added.first else { return }
        XCTAssertEqual(appended.title, "Pasture Movement", file: file, line: line)
        XCTAssertEqual(
            appended.details,
            expectedDetails,
            "The newly appended movement event must persist the exact source-to-destination Pasture payload.",
            file: file,
            line: line
        )
    }

    private static func multisetCounts<T: Hashable>(_ values: [T]) -> [T: Int] {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
    }

    private static func assertMovedAnimalPreservesNonPastureState(
        _ actual: AnimalDetailSnapshot,
        before: AnimalDetailSnapshot,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.id, before.id, file: file, line: line)
        XCTAssertEqual(actual.name, before.name, file: file, line: line)
        XCTAssertEqual(actual.displayTagNumber, before.displayTagNumber, file: file, line: line)
        XCTAssertEqual(actual.displayTagColorID, before.displayTagColorID, file: file, line: line)
        XCTAssertEqual(actual.sex, before.sex, file: file, line: line)
        XCTAssertEqual(actual.animalType, before.animalType, file: file, line: line)
        XCTAssertEqual(actual.birthDate, before.birthDate, file: file, line: line)
        XCTAssertEqual(actual.status, before.status, file: file, line: line)
        XCTAssertEqual(actual.sireID, before.sireID, file: file, line: line)
        XCTAssertEqual(actual.sire, before.sire, file: file, line: line)
        XCTAssertEqual(actual.damID, before.damID, file: file, line: line)
        XCTAssertEqual(actual.dam, before.dam, file: file, line: line)
        XCTAssertEqual(actual.distinguishingFeatures, before.distinguishingFeatures, file: file, line: line)
        XCTAssertEqual(actual.saleDate, before.saleDate, file: file, line: line)
        XCTAssertEqual(actual.salePrice, before.salePrice, file: file, line: line)
        XCTAssertEqual(actual.reasonSold, before.reasonSold, file: file, line: line)
        XCTAssertEqual(actual.deathDate, before.deathDate, file: file, line: line)
        XCTAssertEqual(actual.causeOfDeath, before.causeOfDeath, file: file, line: line)
        XCTAssertEqual(actual.statusReferenceID, before.statusReferenceID, file: file, line: line)
        XCTAssertEqual(actual.statusReferenceName, before.statusReferenceName, file: file, line: line)
        XCTAssertEqual(actual.location, before.location, file: file, line: line)
        XCTAssertEqual(Set(actual.activeTags), Set(before.activeTags), file: file, line: line)
        XCTAssertEqual(Set(actual.inactiveTags), Set(before.inactiveTags), file: file, line: line)
        XCTAssertEqual(actual.isArchived, before.isArchived, file: file, line: line)
        XCTAssertEqual(actual.archivedAt, before.archivedAt, file: file, line: line)
        XCTAssertEqual(actual.archiveReason, before.archiveReason, file: file, line: line)
        XCTAssertEqual(
            actual.maternalOffspringCountIncludingArchived,
            before.maternalOffspringCountIncludingArchived,
            "Moving a resident during Pasture deletion must preserve the dam's archived-inclusive offspring count.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(actual.maternalOffspring.map(\.id)),
            Set(before.maternalOffspring.map(\.id)),
            "Moving a resident during Pasture deletion must preserve visible maternal-offspring inverse membership.",
            file: file,
            line: line
        )
    }

    private static func assertSurvivingPastureCountProjections(
        pastureID: UUID,
        expectedResidentCount: Int,
        pastureRepository: any PastureRepository,
        dashboardRecords: DashboardRecords,
        dashboardPastures: [DashboardPastureRecord],
        file: StaticString,
        line: UInt
    ) throws {
        let detail = try XCTUnwrap(
            pastureRepository.fetchPastureDetail(id: pastureID),
            "A surviving move destination must remain visible through Pasture detail.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            detail.activeAnimalCount,
            expectedResidentCount,
            "Destination Pasture detail active-head count must match its fresh resident projection.",
            file: file,
            line: line
        )

        let summary = try XCTUnwrap(
            pastureRepository.fetchPastures().first { $0.id == pastureID },
            "A surviving move destination must remain visible through the Pasture list.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            summary.activeAnimalCount,
            expectedResidentCount,
            "Destination Pasture list active-head count must match its fresh resident projection.",
            file: file,
            line: line
        )

        if let groupID = detail.groupID {
            let group = try XCTUnwrap(
                pastureRepository.fetchPastureGroupDetail(id: groupID),
                "A grouped move destination must remain visible through its PastureGroup detail.",
                file: file,
                line: line
            )
            let groupedDestination = try XCTUnwrap(
                group.pastures.first { $0.id == pastureID },
                "The surviving destination must remain embedded in its PastureGroup detail.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                groupedDestination.activeAnimalCount,
                expectedResidentCount,
                "PastureGroup detail must expose the destination's updated active-head count.",
                file: file,
                line: line
            )
        }

        let dashboardRecordPasture = try XCTUnwrap(
            dashboardRecords.pastures.first { $0.id == pastureID },
            "A surviving move destination must remain visible in Dashboard records.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            dashboardRecordPasture.activeAnimalCount,
            expectedResidentCount,
            "Dashboard records must expose the destination Pasture resident count after movement.",
            file: file,
            line: line
        )

        let dashboardListPasture = try XCTUnwrap(
            dashboardPastures.first { $0.id == pastureID },
            "A surviving move destination must remain visible in the Dashboard Pasture-list projection.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            dashboardListPasture.activeAnimalCount,
            expectedResidentCount,
            "Dashboard Pasture-list count must match the destination resident projection after movement.",
            file: file,
            line: line
        )
    }

    private static func assertDashboardMovePreservesNonPastureState(
        _ actual: DashboardAnimalRecord,
        before: DashboardAnimalRecord,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.id, before.id, file: file, line: line)
        XCTAssertEqual(actual.displayTagNumber, before.displayTagNumber, file: file, line: line)
        XCTAssertEqual(actual.displayTagColorID, before.displayTagColorID, file: file, line: line)
        XCTAssertEqual(actual.damID, before.damID, file: file, line: line)
        XCTAssertEqual(actual.damDisplayTagNumber, before.damDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(actual.damDisplayTagColorID, before.damDisplayTagColorID, file: file, line: line)
        XCTAssertEqual(actual.sex, before.sex, file: file, line: line)
        XCTAssertEqual(actual.animalType, before.animalType, file: file, line: line)
        XCTAssertEqual(actual.status, before.status, file: file, line: line)
        XCTAssertEqual(actual.isArchived, before.isArchived, file: file, line: line)
        XCTAssertEqual(actual.location, before.location, file: file, line: line)
        XCTAssertEqual(actual.lastPregnancyCheckDate, before.lastPregnancyCheckDate, file: file, line: line)
        XCTAssertEqual(actual.lastPregnancyStatus, before.lastPregnancyStatus, file: file, line: line)
        XCTAssertEqual(actual.expectedCalvingDate, before.expectedCalvingDate, file: file, line: line)
        XCTAssertEqual(actual.lastTreatmentDate, before.lastTreatmentDate, file: file, line: line)
        XCTAssertEqual(actual.birthDate, before.birthDate, file: file, line: line)
        XCTAssertEqual(actual.saleDate, before.saleDate, file: file, line: line)
        XCTAssertEqual(actual.deathDate, before.deathDate, file: file, line: line)
        XCTAssertEqual(
            multisetCounts(actual.healthRecords),
            multisetCounts(before.healthRecords),
            "Pasture deletion movement must preserve Dashboard health-history data without depending on relationship order.",
            file: file,
            line: line
        )
        XCTAssertEqual(actual.offspringCount, before.offspringCount, file: file, line: line)
    }

    private static func assertDashboardRecordsSemanticallyEqual(
        _ actual: DashboardAnimalRecord,
        _ expected: DashboardAnimalRecord,
        file: StaticString,
        line: UInt
    ) {
        assertDashboardMovePreservesNonPastureState(
            actual,
            before: expected,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.pastureID, expected.pastureID, file: file, line: line)
        XCTAssertEqual(actual.pastureName, expected.pastureName, file: file, line: line)
    }

    private static func assertArchivedSession(
        _ actual: FieldCheckSessionDetailSnapshot,
        preserves before: FieldCheckSessionDetailSnapshot,
        archivedAt: Date,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.id, before.id, file: file, line: line)
        XCTAssertEqual(actual.startedAt, before.startedAt, file: file, line: line)
        XCTAssertEqual(actual.completedAt, before.completedAt, file: file, line: line)
        XCTAssertEqual(actual.notes, before.notes, file: file, line: line)
        XCTAssertEqual(actual.pastureID, before.pastureID, file: file, line: line)
        XCTAssertEqual(actual.pastureName, before.pastureName, file: file, line: line)
        XCTAssertEqual(actual.pastureArchivedAt, archivedAt, file: file, line: line)
        XCTAssertTrue(actual.isPastureArchived, file: file, line: line)
        XCTAssertEqual(actual.expectedHeadCountSnapshot, before.expectedHeadCountSnapshot, file: file, line: line)
        XCTAssertEqual(actual.quickCowCount, before.quickCowCount, file: file, line: line)
        XCTAssertEqual(actual.quickHeiferCount, before.quickHeiferCount, file: file, line: line)
        XCTAssertEqual(actual.quickCalfCount, before.quickCalfCount, file: file, line: line)
        XCTAssertEqual(actual.quickBullCount, before.quickBullCount, file: file, line: line)
        XCTAssertEqual(actual.quickSteerCount, before.quickSteerCount, file: file, line: line)
        XCTAssertEqual(Set(actual.animalChecks), Set(before.animalChecks), file: file, line: line)
        XCTAssertEqual(Set(actual.findings), Set(before.findings), file: file, line: line)
    }

    private static func assertSessionUnchanged(
        _ actual: FieldCheckSessionDetailSnapshot,
        expected: FieldCheckSessionDetailSnapshot,
        message: String,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.id, expected.id, message, file: file, line: line)
        XCTAssertEqual(actual.startedAt, expected.startedAt, message, file: file, line: line)
        XCTAssertEqual(actual.completedAt, expected.completedAt, message, file: file, line: line)
        XCTAssertEqual(actual.notes, expected.notes, message, file: file, line: line)
        XCTAssertEqual(actual.pastureID, expected.pastureID, message, file: file, line: line)
        XCTAssertEqual(actual.pastureName, expected.pastureName, message, file: file, line: line)
        XCTAssertEqual(actual.pastureArchivedAt, expected.pastureArchivedAt, message, file: file, line: line)
        XCTAssertEqual(actual.isPastureArchived, expected.isPastureArchived, message, file: file, line: line)
        XCTAssertEqual(actual.expectedHeadCountSnapshot, expected.expectedHeadCountSnapshot, message, file: file, line: line)
        XCTAssertEqual(actual.quickCowCount, expected.quickCowCount, message, file: file, line: line)
        XCTAssertEqual(actual.quickHeiferCount, expected.quickHeiferCount, message, file: file, line: line)
        XCTAssertEqual(actual.quickCalfCount, expected.quickCalfCount, message, file: file, line: line)
        XCTAssertEqual(actual.quickBullCount, expected.quickBullCount, message, file: file, line: line)
        XCTAssertEqual(actual.quickSteerCount, expected.quickSteerCount, message, file: file, line: line)
        XCTAssertEqual(Set(actual.animalChecks), Set(expected.animalChecks), message, file: file, line: line)
        XCTAssertEqual(Set(actual.findings), Set(expected.findings), message, file: file, line: line)
    }
}
