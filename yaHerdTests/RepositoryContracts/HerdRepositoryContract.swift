import Foundation
import XCTest
@testable import yaHerd

/// Target-only test control used to establish deterministic Herd workspace state.
///
/// The production repository remains persistence-neutral. A Core Data contract runner supplies
/// these hooks so the permanent contract can prove that the selected/current Herd is resolved by
/// application UUID instead of by arbitrary persistence fetch order.
@MainActor
struct HerdRepositorySelectionTestControl {
    let seedHerd: (
        _ id: UUID,
        _ name: String,
        _ createdAt: Date,
        _ updatedAt: Date
    ) throws -> Void
    let selectCurrentHerd: (_ id: UUID) throws -> Void
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
    static func assertMissingReadDoesNotBootstrapHerd(
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

        // A read must remain a read. A fresh repository should still observe an empty store rather
        // than a Herd created as a side effect of the first fetch.
        assertMissingHerd(
            try fixture.makeHerdRepository().fetchCurrentHerd(),
            file: file,
            line: line
        )
    }

    static func assertRenameCanBootstrapCurrentHerdAndSurvivesReload(
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

        let created = try repository.renameCurrentHerd(to: "  Contract Herd  ")
        XCTAssertEqual(created.name, "Contract Herd", file: file, line: line)
        XCTAssertEqual(created.id, created.publicID, file: file, line: line)
        XCTAssertTrue(
            created.updatedAt >= created.createdAt,
            "A rename-created Herd must expose coherent creation/update metadata.",
            file: file,
            line: line
        )

        let reloaded = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(
            reloaded,
            created,
            "The application Herd UUID and metadata must survive repository reload.",
            file: file,
            line: line
        )

        let renamed = try fixture.makeHerdRepository().renameCurrentHerd(to: "  Contract Herd Renamed\n")
        XCTAssertEqual(renamed.publicID, created.publicID, "Rename must preserve application identity.", file: file, line: line)
        XCTAssertEqual(renamed.createdAt, created.createdAt, "Rename must preserve creation metadata.", file: file, line: line)
        XCTAssertEqual(renamed.name, "Contract Herd Renamed", file: file, line: line)
        XCTAssertTrue(
            renamed.updatedAt >= created.updatedAt,
            "Rename must not move update metadata backward.",
            file: file,
            line: line
        )

        let renamedReload = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(renamedReload, renamed, file: file, line: line)
    }

    static func assertEmptyRenameIsRejectedWithoutBootstrapping(
        using fixture: HerdRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertThrowsError(
            try fixture.makeHerdRepository().renameCurrentHerd(to: " \n\t "),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? HerdRepositoryError, .emptyName, file: file, line: line)
        }

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
        let createdAt = fixedDate(1_700_000_000)
        let updatedAt = fixedDate(1_700_000_500)
        try fixture.selectionControl.seedHerd(
            herdID,
            "Existing Contract Herd",
            createdAt,
            updatedAt
        )
        try fixture.selectionControl.selectCurrentHerd(herdID)

        let before = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(before.publicID, herdID, file: file, line: line)

        XCTAssertThrowsError(
            try fixture.makeHerdRepository().renameCurrentHerd(to: "   "),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? HerdRepositoryError, .emptyName, file: file, line: line)
        }

        let after = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(
            after,
            before,
            "Validation failure must leave persisted Herd state unchanged.",
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
        let selectedCreatedAt = fixedDate(1_700_000_000)
        let selectedUpdatedAt = fixedDate(1_700_000_100)

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
        try fixture.selectionControl.selectCurrentHerd(selectedID)

        let selected = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(selected.publicID, selectedID, file: file, line: line)
        XCTAssertEqual(selected.name, "Selected Herd", file: file, line: line)
        XCTAssertEqual(selected.createdAt, selectedCreatedAt, file: file, line: line)
        XCTAssertEqual(selected.updatedAt, selectedUpdatedAt, file: file, line: line)

        let renamedSelected = try fixture.makeHerdRepository().renameCurrentHerd(to: "  Selected Herd Renamed  ")
        XCTAssertEqual(renamedSelected.publicID, selectedID, file: file, line: line)
        XCTAssertEqual(renamedSelected.createdAt, selectedCreatedAt, file: file, line: line)
        XCTAssertEqual(renamedSelected.name, "Selected Herd Renamed", file: file, line: line)

        try fixture.selectionControl.selectCurrentHerd(olderID)
        let older = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(older.publicID, olderID, file: file, line: line)
        XCTAssertEqual(older.name, "Older Noncurrent Herd", "Renaming the selected Herd must not mutate another Herd.", file: file, line: line)
        XCTAssertEqual(older.createdAt, olderCreatedAt, file: file, line: line)
        XCTAssertEqual(older.updatedAt, olderUpdatedAt, file: file, line: line)

        try fixture.selectionControl.selectCurrentHerd(selectedID)
        let selectedReload = try fixture.makeHerdRepository().fetchCurrentHerd()
        XCTAssertEqual(selectedReload.publicID, selectedID, file: file, line: line)
        XCTAssertEqual(selectedReload.name, "Selected Herd Renamed", file: file, line: line)
        XCTAssertEqual(selectedReload.createdAt, selectedCreatedAt, file: file, line: line)
    }

    static func assertMissingSelectedHerdDoesNotFallBackToAnotherStoredHerd(
        using fixture: HerdRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let storedID = UUID()
        try fixture.selectionControl.seedHerd(
            storedID,
            "Stored But Not Selected",
            fixedDate(1_700_100_000),
            fixedDate(1_700_100_100)
        )
        try fixture.selectionControl.selectCurrentHerd(UUID())

        assertMissingHerd(
            try fixture.makeHerdRepository().fetchCurrentHerd(),
            file: file,
            line: line
        )
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
