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
}

/// Permanent persistence-neutral behavioral contract for `HerdRepository` implementations.
///
/// These assertions protect the Domain-visible Herd workspace behavior that must survive the
/// Core Data cutover. The contract intentionally has no SwiftData runner. The production Core Data
/// repository will execute it once Herd persistence and current-workspace selection are implemented.
@MainActor
struct HerdRepositoryContractFixture {
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
    }

    static func assertCurrentHerdSelectionUsesApplicationIdentityAndScopesRename(
        using fixture: HerdRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let olderID = UUID()
        let selectedID = UUID()
        let olderCreatedAt = fixedDate(1_650_000_000)
        let olderUpdatedAt = fixedDate(1_650_000_100)
        let selectedCreatedAt = fixedDate(1_700_100_000)
        let selectedUpdatedAt = fixedDate(1_700_100_100)

        // Seed the older Herd first so an implementation that simply returns the first/oldest
        // persistence row cannot accidentally satisfy the contract.
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
        try fixture.selectionControl.setCurrentHerdID(selectedID)

        let selected = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(selected.publicID, selectedID, file: file, line: line)
        XCTAssertEqual(selected.name, "Selected Herd", file: file, line: line)
        XCTAssertEqual(selected.createdAt, selectedCreatedAt, file: file, line: line)
        XCTAssertEqual(selected.updatedAt, selectedUpdatedAt, file: file, line: line)

        let renamedSelected = try fixture.makeHerdRepository().renameCurrentHerd(
            to: "  Selected Herd Renamed  "
        )
        XCTAssertEqual(renamedSelected.publicID, selectedID, file: file, line: line)
        XCTAssertEqual(renamedSelected.createdAt, selectedCreatedAt, file: file, line: line)
        XCTAssertEqual(renamedSelected.name, "Selected Herd Renamed", file: file, line: line)
        XCTAssertGreaterThan(renamedSelected.updatedAt, selectedUpdatedAt, file: file, line: line)

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

        try fixture.selectionControl.setCurrentHerdID(selectedID)
        let selectedReload = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(selectedReload.publicID, selectedID, file: file, line: line)
        XCTAssertEqual(selectedReload.name, "Selected Herd Renamed", file: file, line: line)
        XCTAssertEqual(selectedReload.createdAt, selectedCreatedAt, file: file, line: line)
        XCTAssertEqual(selectedReload.updatedAt, renamedSelected.updatedAt, file: file, line: line)
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
