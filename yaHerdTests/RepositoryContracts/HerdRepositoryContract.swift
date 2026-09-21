import Foundation
import XCTest
@testable import yaHerd

/// Target-only test control used to establish deterministic Herd workspace state.
///
/// The production repository remains persistence-neutral. A Core Data contract runner supplies
/// these hooks so the permanent contract can prove that the selected/current Herd is resolved by
/// application UUID instead of by arbitrary persistence fetch order. The current-Herd hook accepts
/// both nil and stale UUIDs so missing-selection recovery behavior can be characterized explicitly.
@MainActor
struct HerdRepositorySelectionTestControl {
    let seedHerd: (
        _ id: UUID,
        _ name: String,
        _ createdAt: Date,
        _ updatedAt: Date
    ) throws -> Void
    let setCurrentHerdID: (_ id: UUID?) throws -> Void

    /// Returns physical persisted Herd-row multiplicity grouped by application UUID regardless of
    /// current selection. The future Core Data runner must read this through a fresh unscoped
    /// persistence access scope so hidden/unselected roots — including duplicate physical rows that
    /// share one application UUID — cannot be filtered away or collapsed by the test control.
    ///
    /// Generic rejection of intentionally seeded duplicate application UUIDs remains owned by
    /// `IdentityContract`; this probe only proves Herd operations preserve durable row multiplicity keyed by application UUID.
    let persistedHerdRowCountsByID: () throws -> [UUID: Int]
}

/// Distinguishes the intended post-mutation commit failpoint from validation or lookup failures.
enum HerdRepositoryRollbackInjectedError: Error, Equatable {
    case afterRenameStaged
}

/// Target-only fault-injection hook for the future Core Data Herd repository.
///
/// The runner must configure the supplied repository so `renameCurrentHerd(to:)` stages the normalized
/// name and update timestamp, then fails at the final persistence commit and surfaces
/// `HerdRepositoryRollbackInjectedError.afterRenameStaged`. The failpoint must be removed before the
/// closure returns so the same repository can be used to prove post-rollback recovery.
@MainActor
struct HerdRepositoryRollbackFailureInjection {
    let renameCurrentHerdFailingAfterMutationStaged: (
        _ repository: any HerdRepository,
        _ name: String
    ) throws -> Void
}

/// Permanent persistence-neutral behavioral contract fixture for `HerdRepository` implementations.
///
/// The assertions below protect the Domain-visible Herd workspace behavior that must survive the
/// Core Data cutover. The contract intentionally has no SwiftData runner. The production Core Data
/// repository will execute it once Herd persistence and current-workspace selection are implemented.
///
/// A runner must create a newly isolated backing store and selection source for each top-level
/// contract assertion. Assertions intentionally seed exact Herd sets and are not designed to run
/// sequentially against persistence left behind by another assertion.
@MainActor
struct HerdRepositoryContractFixture {
    /// Every invocation within one top-level assertion must return a new repository backed by a
    /// fresh persistence access scope over that assertion's same isolated test store and current-Herd
    /// selection source. This makes fresh-reload assertions independent from an earlier context
    /// without changing the durable scenario established by the assertion.
    let makeHerdRepository: () -> any HerdRepository
    let selectionControl: HerdRepositorySelectionTestControl
}

@MainActor
enum HerdRepositoryContract {
    static func assertMissingReadAndRenameDoNotBootstrapHerd(
        using fixture: HerdRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeHerdRepository()

        assertMissingHerd(
            try repository.fetchCurrentHerd(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.selectionControl.persistedHerdRowCountsByID(),
            [:],
            "A failed current-Herd read on an empty store must not create a hidden Herd root.",
            file: file,
            line: line
        )
        assertMissingHerd(
            try repository.renameCurrentHerd(to: "Contract Herd"),
            file: file,
            line: line
        )

        // A failed rename must leave the same repository usable and empty.
        assertMissingHerd(
            try repository.fetchCurrentHerd(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.selectionControl.persistedHerdRowCountsByID(),
            [:],
            "Failed reads/rename on an empty store must not create a hidden or unselected Herd root.",
            file: file,
            line: line
        )

        // Herd creation belongs to the explicit bootstrap/onboarding boundary. Repository reads or
        // ordinary rename mutations must not invent a root merely because persistence is empty.
        assertMissingHerd(
            try fixture.makeHerdRepository().fetchCurrentHerd(),
            file: file,
            line: line
        )
    }

    static func assertRenameNormalizesNamePreservesIdentityAndSurvivesReload(
        using fixture: HerdRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let herdID = UUID()
        let createdAt = fixedDate(1_700_000_000)
        let updatedAt = fixedDate(1_700_000_500)
        try fixture.selectionControl.seedHerd(
            herdID,
            "Existing Contract Herd",
            createdAt,
            updatedAt
        )
        try fixture.selectionControl.setCurrentHerdID(herdID)

        let repository = fixture.makeHerdRepository()
        let before = try repository.fetchCurrentHerd()
        XCTAssertEqual(before.publicID, herdID, file: file, line: line)
        XCTAssertEqual(before.id, herdID, file: file, line: line)
        XCTAssertEqual(before.name, "Existing Contract Herd", file: file, line: line)
        XCTAssertEqual(before.createdAt, createdAt, file: file, line: line)
        XCTAssertEqual(before.updatedAt, updatedAt, file: file, line: line)

        let renamed = try repository.renameCurrentHerd(
            to: "  Contract   Herd Renamed\n"
        )
        XCTAssertEqual(renamed.publicID, herdID, "Rename must preserve application identity.", file: file, line: line)
        XCTAssertEqual(renamed.createdAt, createdAt, "Rename must preserve creation metadata.", file: file, line: line)
        XCTAssertEqual(
            renamed.name,
            "Contract   Herd Renamed",
            "Rename trims surrounding whitespace without rewriting meaningful internal whitespace.",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            renamed.updatedAt,
            updatedAt,
            "A successful rename must advance update metadata.",
            file: file,
            line: line
        )

        let sameRepository = try repository.fetchCurrentHerd()
        XCTAssertEqual(
            sameRepository,
            renamed,
            "The successful rename must be immediately observable through the same repository.",
            file: file,
            line: line
        )

        let reloaded = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(
            reloaded,
            renamed,
            "The same Herd UUID, normalized name, and metadata must survive repository reload.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.selectionControl.persistedHerdRowCountsByID(),
            [herdID: 1],
            "Rename must leave exactly one durable Herd row for the selected application UUID.",
            file: file,
            line: line
        )
    }

    static func assertRenamePersistenceFailureRollsBackAndRepositoryRecovers(
        using fixture: HerdRepositoryContractFixture,
        failureInjection: HerdRepositoryRollbackFailureInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let selectedID = UUID()
        let controlID = UUID()
        let selectedCreatedAt = fixedDate(1_700_005_000)
        let selectedUpdatedAt = fixedDate(1_700_005_500)
        let controlCreatedAt = fixedDate(1_700_006_000)
        let controlUpdatedAt = fixedDate(1_700_006_500)

        try fixture.selectionControl.seedHerd(
            selectedID,
            "Rollback Contract Herd",
            selectedCreatedAt,
            selectedUpdatedAt
        )
        try fixture.selectionControl.seedHerd(
            controlID,
            "Unrelated Rollback Control Herd",
            controlCreatedAt,
            controlUpdatedAt
        )
        try fixture.selectionControl.setCurrentHerdID(selectedID)

        let repository = fixture.makeHerdRepository()
        let before = try repository.fetchCurrentHerd()

        XCTAssertThrowsError(
            try failureInjection.renameCurrentHerdFailingAfterMutationStaged(
                repository,
                "  Must Roll Back  "
            ),
            "The injected rename must reach the post-mutation persistence failpoint.",
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? HerdRepositoryRollbackInjectedError,
                .afterRenameStaged,
                "The rename must fail at the configured post-mutation failpoint rather than during unrelated validation or lookup.",
                file: file,
                line: line
            )
        }

        let sameRepositoryAfterFailure = try repository.fetchCurrentHerd()
        XCTAssertEqual(
            sameRepositoryAfterFailure,
            before,
            "A failed persistence commit must roll back the staged Herd name and update timestamp in the same repository.",
            file: file,
            line: line
        )

        let freshRepositoryAfterFailure = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(
            freshRepositoryAfterFailure,
            before,
            "A failed persistence commit must leave durable Herd state unchanged.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.selectionControl.persistedHerdRowCountsByID(),
            [selectedID: 1, controlID: 1],
            "A failed rename must not change the durable Herd UUIDs or their physical row multiplicity.",
            file: file,
            line: line
        )

        try fixture.selectionControl.setCurrentHerdID(controlID)
        let controlAfterFailure = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(controlAfterFailure.publicID, controlID, file: file, line: line)
        XCTAssertEqual(controlAfterFailure.name, "Unrelated Rollback Control Herd", file: file, line: line)
        XCTAssertEqual(controlAfterFailure.createdAt, controlCreatedAt, file: file, line: line)
        XCTAssertEqual(
            controlAfterFailure.updatedAt,
            controlUpdatedAt,
            "The failed selected-Herd rename must not mutate an unrelated stored Herd.",
            file: file,
            line: line
        )

        try fixture.selectionControl.setCurrentHerdID(selectedID)
        let recovered = try repository.renameCurrentHerd(to: "  Recovered Herd  ")
        XCTAssertEqual(recovered.publicID, selectedID, file: file, line: line)
        XCTAssertEqual(recovered.createdAt, selectedCreatedAt, file: file, line: line)
        XCTAssertEqual(recovered.name, "Recovered Herd", file: file, line: line)
        XCTAssertGreaterThan(
            recovered.updatedAt,
            selectedUpdatedAt,
            "The same repository must remain usable for a later successful rename after rollback.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeHerdRepository().fetchCurrentHerd(),
            recovered,
            "The recovery rename must commit normally after the injected failure is cleared.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.selectionControl.persistedHerdRowCountsByID(),
            [selectedID: 1, controlID: 1],
            "Recovery must preserve the exact durable Herd UUID-to-row-count snapshot.",
            file: file,
            line: line
        )

        try fixture.selectionControl.setCurrentHerdID(controlID)
        let control = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(control.publicID, controlID, file: file, line: line)
        XCTAssertEqual(control.name, "Unrelated Rollback Control Herd", file: file, line: line)
        XCTAssertEqual(control.createdAt, controlCreatedAt, file: file, line: line)
        XCTAssertEqual(
            control.updatedAt,
            controlUpdatedAt,
            "Neither the failed rename nor recovery of the selected Herd may mutate an unrelated stored Herd.",
            file: file,
            line: line
        )
    }

    static func assertEmptyRenameIsRejectedWithoutBootstrapping(
        using fixture: HerdRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeHerdRepository()

        XCTAssertThrowsError(
            try repository.renameCurrentHerd(to: " \n\t "),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? HerdRepositoryError, .emptyName, file: file, line: line)
        }

        assertMissingHerd(
            try repository.fetchCurrentHerd(),
            file: file,
            line: line
        )
        assertMissingHerd(
            try fixture.makeHerdRepository().fetchCurrentHerd(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.selectionControl.persistedHerdRowCountsByID(),
            [:],
            "Whitespace-only rename on an empty store must not bootstrap a hidden Herd.",
            file: file,
            line: line
        )
    }

    static func assertEmptyRenameDoesNotMutateExistingHerd(
        using fixture: HerdRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let herdID = UUID()
        let createdAt = fixedDate(1_700_010_000)
        let updatedAt = fixedDate(1_700_010_500)
        try fixture.selectionControl.seedHerd(
            herdID,
            "Existing Contract Herd",
            createdAt,
            updatedAt
        )
        try fixture.selectionControl.setCurrentHerdID(herdID)

        let repository = fixture.makeHerdRepository()
        let before = try repository.fetchCurrentHerd()

        XCTAssertThrowsError(
            try repository.renameCurrentHerd(to: "   "),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? HerdRepositoryError, .emptyName, file: file, line: line)
        }

        let sameRepository = try repository.fetchCurrentHerd()
        XCTAssertEqual(
            sameRepository,
            before,
            "Validation failure must leave same-repository Herd state unchanged and readable.",
            file: file,
            line: line
        )

        let reloaded = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(
            reloaded,
            before,
            "Validation failure must leave durable Herd state unchanged.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.selectionControl.persistedHerdRowCountsByID(),
            [herdID: 1],
            "Validation failure must not change the durable Herd UUIDs or their physical row multiplicity.",
            file: file,
            line: line
        )
    }

    static func assertCurrentHerdSelectionUsesApplicationIdentityAndScopesRename(
        using fixture: HerdRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let olderID = UUID()
        let selectedID = UUID()
        let newerID = UUID()
        let olderCreatedAt = fixedDate(1_650_000_000)
        let olderUpdatedAt = fixedDate(1_650_000_100)
        let selectedCreatedAt = fixedDate(1_700_100_000)
        let selectedUpdatedAt = fixedDate(1_700_100_100)
        let newerCreatedAt = fixedDate(1_750_000_000)
        let newerUpdatedAt = fixedDate(1_750_000_100)

        // Select the middle Herd by application UUID. With both an older/first-inserted and a
        // newer/last-inserted control, implementations that choose first, last, oldest, or newest
        // persistence rows cannot accidentally satisfy the contract.
        try fixture.selectionControl.seedHerd(
            olderID,
            "Older Noncurrent Herd",
            olderCreatedAt,
            olderUpdatedAt
        )
        try fixture.selectionControl.seedHerd(
            selectedID,
            "Selected Herd",
            selectedCreatedAt,
            selectedUpdatedAt
        )
        try fixture.selectionControl.seedHerd(
            newerID,
            "Newer Noncurrent Herd",
            newerCreatedAt,
            newerUpdatedAt
        )
        try fixture.selectionControl.setCurrentHerdID(selectedID)

        let selectedRepository = fixture.makeHerdRepository()
        let selected = try selectedRepository.fetchCurrentHerd()
        XCTAssertEqual(selected.publicID, selectedID, file: file, line: line)
        XCTAssertEqual(selected.name, "Selected Herd", file: file, line: line)
        XCTAssertEqual(selected.createdAt, selectedCreatedAt, file: file, line: line)
        XCTAssertEqual(selected.updatedAt, selectedUpdatedAt, file: file, line: line)
        XCTAssertEqual(
            try fixture.selectionControl.persistedHerdRowCountsByID(),
            [olderID: 1, selectedID: 1, newerID: 1],
            "Resolving the selected Herd must not change durable Herd UUIDs or physical row multiplicity.",
            file: file,
            line: line
        )

        let renamedSelected = try selectedRepository.renameCurrentHerd(
            to: "  Selected Herd Renamed  "
        )
        XCTAssertEqual(renamedSelected.publicID, selectedID, file: file, line: line)
        XCTAssertEqual(renamedSelected.createdAt, selectedCreatedAt, file: file, line: line)
        XCTAssertEqual(renamedSelected.name, "Selected Herd Renamed", file: file, line: line)
        XCTAssertGreaterThan(renamedSelected.updatedAt, selectedUpdatedAt, file: file, line: line)
        XCTAssertEqual(
            try selectedRepository.fetchCurrentHerd(),
            renamedSelected,
            "Renaming the selected Herd must not redirect the same repository to another stored Herd.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.makeHerdRepository().fetchCurrentHerd(),
            renamedSelected,
            "Renaming the selected Herd must leave application selection resolving that same Herd in a fresh repository.",
            file: file,
            line: line
        )

        try fixture.selectionControl.setCurrentHerdID(olderID)
        let older = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(older.publicID, olderID, file: file, line: line)
        XCTAssertEqual(
            older.name,
            "Older Noncurrent Herd",
            "Renaming the selected Herd must not mutate another Herd.",
            file: file,
            line: line
        )
        XCTAssertEqual(older.createdAt, olderCreatedAt, file: file, line: line)
        XCTAssertEqual(older.updatedAt, olderUpdatedAt, file: file, line: line)

        try fixture.selectionControl.setCurrentHerdID(newerID)
        let newer = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(newer.publicID, newerID, file: file, line: line)
        XCTAssertEqual(
            newer.name,
            "Newer Noncurrent Herd",
            "Renaming the selected Herd must not mutate a newer/last-inserted Herd.",
            file: file,
            line: line
        )
        XCTAssertEqual(newer.createdAt, newerCreatedAt, file: file, line: line)
        XCTAssertEqual(newer.updatedAt, newerUpdatedAt, file: file, line: line)

        try fixture.selectionControl.setCurrentHerdID(selectedID)
        let selectedReload = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(selectedReload.publicID, selectedID, file: file, line: line)
        XCTAssertEqual(selectedReload.name, "Selected Herd Renamed", file: file, line: line)
        XCTAssertEqual(selectedReload.createdAt, selectedCreatedAt, file: file, line: line)
        XCTAssertEqual(selectedReload.updatedAt, renamedSelected.updatedAt, file: file, line: line)
        XCTAssertEqual(
            try fixture.selectionControl.persistedHerdRowCountsByID(),
            [olderID: 1, selectedID: 1, newerID: 1],
            "Selected-Herd rename must preserve the complete durable Herd UUID-to-row-count snapshot.",
            file: file,
            line: line
        )
    }

    static func assertMissingCurrentHerdSelectionDoesNotInferStoredHerd(
        using fixture: HerdRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let storedID = UUID()
        let createdAt = fixedDate(1_700_150_000)
        let updatedAt = fixedDate(1_700_150_100)
        try fixture.selectionControl.seedHerd(
            storedID,
            "Stored Without Selection",
            createdAt,
            updatedAt
        )
        try fixture.selectionControl.setCurrentHerdID(nil)

        let repository = fixture.makeHerdRepository()
        assertMissingHerd(
            try repository.fetchCurrentHerd(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.selectionControl.persistedHerdRowCountsByID(),
            [storedID: 1],
            "A missing-selection read must not change durable Herd UUIDs or physical row multiplicity.",
            file: file,
            line: line
        )
        assertMissingHerd(
            try repository.renameCurrentHerd(to: "Must Not Infer"),
            file: file,
            line: line
        )
        assertMissingHerd(
            try repository.fetchCurrentHerd(),
            file: file,
            line: line
        )
        assertMissingHerd(
            try fixture.makeHerdRepository().fetchCurrentHerd(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.selectionControl.persistedHerdRowCountsByID(),
            [storedID: 1],
            "Missing selection must not cause rename to bootstrap another Herd root.",
            file: file,
            line: line
        )

        try fixture.selectionControl.setCurrentHerdID(storedID)
        let stored = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(stored.publicID, storedID, file: file, line: line)
        XCTAssertEqual(stored.name, "Stored Without Selection", file: file, line: line)
        XCTAssertEqual(stored.createdAt, createdAt, file: file, line: line)
        XCTAssertEqual(stored.updatedAt, updatedAt, file: file, line: line)
    }

    static func assertStaleCurrentHerdSelectionDoesNotFallBackToAnotherStoredHerd(
        using fixture: HerdRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let storedID = UUID()
        let storedCreatedAt = fixedDate(1_700_200_000)
        let storedUpdatedAt = fixedDate(1_700_200_100)
        try fixture.selectionControl.seedHerd(
            storedID,
            "Stored But Not Selected",
            storedCreatedAt,
            storedUpdatedAt
        )
        try fixture.selectionControl.setCurrentHerdID(UUID())

        let repository = fixture.makeHerdRepository()
        assertMissingHerd(
            try repository.fetchCurrentHerd(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.selectionControl.persistedHerdRowCountsByID(),
            [storedID: 1],
            "A stale-selection read must not change durable Herd UUIDs or physical row multiplicity, or fall back to another Herd.",
            file: file,
            line: line
        )
        assertMissingHerd(
            try repository.renameCurrentHerd(to: "Must Not Fall Back"),
            file: file,
            line: line
        )
        assertMissingHerd(
            try repository.fetchCurrentHerd(),
            file: file,
            line: line
        )
        assertMissingHerd(
            try fixture.makeHerdRepository().fetchCurrentHerd(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.selectionControl.persistedHerdRowCountsByID(),
            [storedID: 1],
            "Stale selection must not cause rename to bootstrap or fall back by creating another Herd root.",
            file: file,
            line: line
        )

        try fixture.selectionControl.setCurrentHerdID(storedID)
        let stored = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(stored.publicID, storedID, file: file, line: line)
        XCTAssertEqual(stored.name, "Stored But Not Selected", file: file, line: line)
        XCTAssertEqual(stored.createdAt, storedCreatedAt, file: file, line: line)
        XCTAssertEqual(stored.updatedAt, storedUpdatedAt, file: file, line: line)
    }

    private static func assertMissingHerd(
        _ expression: @autoclosure () throws -> HerdSummary,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? HerdRepositoryError, .missingHerd, file: file, line: line)
        }
    }

    private static func fixedDate(_ secondsSince1970: TimeInterval) -> Date {
        Date(timeIntervalSince1970: secondsSince1970)
    }
}
