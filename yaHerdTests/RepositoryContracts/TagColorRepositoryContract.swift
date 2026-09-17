import Foundation
import XCTest
@testable import yaHerd

/// Persistence-neutral snapshot of the UUID references that must survive tag-color identity merges.
///
/// Tag colors are referenced from current animal tags, historical tag rows, and frozen Field Check
/// roster data. The contract runner supplies a target-only probe so the permanent repository contract
/// can verify those references without importing or inspecting a persistence framework.
struct TagColorReferenceSnapshot: Equatable {
    let animalTagColorID: UUID?
    let historicalTagColorID: UUID?
    let fieldCheckRosterTagColorID: UUID?
}

/// Target-only hooks used to establish and inspect tag-color UUID references.
///
/// A Core Data contract runner should seed representative records for all three reference locations
/// and return their current UUID values after repository mutations.
@MainActor
struct TagColorReferenceTestControl {
    let seedReferences: (_ colorID: UUID) throws -> Void
    let fetchReferences: () throws -> TagColorReferenceSnapshot
}

/// Permanent persistence-neutral behavioral contract for `TagColorRepository` implementations.
///
/// These assertions protect the Domain-visible tag-color library behavior that must survive the
/// Core Data cutover. SwiftData migration plumbing, UserDefaults import, physical row layout, and
/// framework-specific duplicate repair are intentionally outside this contract.
@MainActor
struct TagColorRepositoryContractFixture {
    let makeTagColorRepository: () -> any TagColorRepository
    let referenceControl: TagColorReferenceTestControl
}

@MainActor
enum TagColorRepositoryContract {
    static func assertBuiltInLibraryHasStableIdentityOrderingAndWhiteDefault(
        using fixture: TagColorRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let expected = stableProjection(TagColorDefaults.seedDefaultColors())
        let repository = fixture.makeTagColorRepository()

        let firstRead = stableProjection(try repository.fetchColors())
        XCTAssertEqual(firstRead, expected, file: file, line: line)
        XCTAssertEqual(
            firstRead.filter(\.isDefault).map(\.id),
            [TagColorDefaults.whiteID],
            "A pristine library must expose White as the single default color.",
            file: file,
            line: line
        )

        let freshRead = stableProjection(try fixture.makeTagColorRepository().fetchColors())
        XCTAssertEqual(
            freshRead,
            expected,
            "Built-in application identities and ordering must not change across repository instances.",
            file: file,
            line: line
        )
    }

    static func assertUpsertNormalizesPersistsAndPreservesApplicationIdentity(
        using fixture: TagColorRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeTagColorRepository()
        let colorID = UUID()
        let createdAt = fixedDate(1_700_000_000)
        let initialUpdatedAt = fixedDate(1_700_000_100)
        let firstRGBA = RGBAColor(r: 0.1, g: 0.55, b: 0.8, a: 0.9)

        var color = TagColorSnapshot(
            id: colorID,
            name: "Placeholder",
            prefix: "X",
            rgba: firstRGBA,
            sortOrder: 99,
            createdAt: createdAt,
            updatedAt: initialUpdatedAt
        )
        // Mutate after initialization so normalization is exercised at the repository boundary.
        color.name = "  Contract Aqua\n"
        color.prefix = " ca "

        try repository.upsert(color)

        let inserted = try requireColor(
            id: colorID,
            in: fixture.makeTagColorRepository(),
            file: file,
            line: line
        )
        XCTAssertEqual(inserted.name, "Contract Aqua", file: file, line: line)
        XCTAssertEqual(inserted.prefix, "CA", file: file, line: line)
        XCTAssertEqual(inserted.rgba, firstRGBA, file: file, line: line)
        XCTAssertEqual(inserted.createdAt, createdAt, file: file, line: line)
        XCTAssertEqual(inserted.updatedAt, initialUpdatedAt, file: file, line: line)
        XCTAssertFalse(inserted.isDefault, file: file, line: line)

        let secondRGBA = RGBAColor(r: 0.25, g: 0.65, b: 0.35)
        var updated = TagColorSnapshot(
            id: colorID,
            name: "Placeholder",
            prefix: "X",
            rgba: secondRGBA,
            sortOrder: 0,
            createdAt: fixedDate(1_800_000_000),
            updatedAt: fixedDate(1_800_000_100)
        )
        updated.name = "  Contract Aqua Updated  "
        updated.prefix = "   "

        try fixture.makeTagColorRepository().upsert(updated)

        let reloaded = try requireColor(
            id: colorID,
            in: fixture.makeTagColorRepository(),
            file: file,
            line: line
        )
        XCTAssertEqual(reloaded.id, colorID, "Updating must preserve the application UUID.", file: file, line: line)
        XCTAssertEqual(reloaded.name, "Contract Aqua Updated", file: file, line: line)
        XCTAssertEqual(reloaded.prefix, "CAU", file: file, line: line)
        XCTAssertEqual(reloaded.rgba, secondRGBA, file: file, line: line)
        XCTAssertEqual(
            reloaded.createdAt,
            createdAt,
            "Repository updates must not replace creation metadata supplied by the original record.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            reloaded.updatedAt >= inserted.updatedAt,
            "Updating a color must not move update metadata backward.",
            file: file,
            line: line
        )
    }

    static func assertEmptyNameUpsertIsNoOp(
        using fixture: TagColorRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeTagColorRepository()
        let before = stableProjection(try repository.fetchColors())

        var invalid = TagColorSnapshot(
            name: "Placeholder",
            prefix: "P",
            rgba: RGBAColor(r: 0.4, g: 0.4, b: 0.4)
        )
        invalid.name = "  \n\t  "

        try repository.upsert(invalid)

        let after = stableProjection(try fixture.makeTagColorRepository().fetchColors())
        XCTAssertEqual(
            after,
            before,
            "A whitespace-only name must not create, replace, or reorder library entries.",
            file: file,
            line: line
        )
    }

    static func assertDefaultSelectionIsExclusivePersistentAndUnaffectedByUnknownIDs(
        using fixture: TagColorRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeTagColorRepository()
        try repository.setDefaultColor(id: TagColorDefaults.blueID)

        var colors = try fixture.makeTagColorRepository().fetchColors()
        XCTAssertEqual(defaultColorIDs(in: colors), [TagColorDefaults.blueID], file: file, line: line)

        let beforeUnknownSelection = stableProjection(colors)
        try fixture.makeTagColorRepository().setDefaultColor(id: UUID())
        colors = try fixture.makeTagColorRepository().fetchColors()
        XCTAssertEqual(
            stableProjection(colors),
            beforeUnknownSelection,
            "Selecting an unknown UUID must be a no-op.",
            file: file,
            line: line
        )

        let customID = UUID()
        let custom = TagColorSnapshot(
            id: customID,
            name: "Contract Default",
            prefix: "CD",
            rgba: RGBAColor(r: 0.15, g: 0.25, b: 0.75)
        )
        try fixture.makeTagColorRepository().upsert(custom)
        try fixture.makeTagColorRepository().setDefaultColor(id: customID)

        colors = try fixture.makeTagColorRepository().fetchColors()
        XCTAssertEqual(defaultColorIDs(in: colors), [customID], file: file, line: line)

        var edited = custom
        edited.name = "Contract Default Edited"
        edited.prefix = "CDE"
        edited.rgba = RGBAColor(r: 0.3, g: 0.4, b: 0.9)
        edited.isDefault = false
        try fixture.makeTagColorRepository().upsert(edited)

        let reloaded = try fixture.makeTagColorRepository().fetchColors()
        XCTAssertEqual(
            defaultColorIDs(in: reloaded),
            [customID],
            "Editing the currently selected default must not implicitly clear the default preference.",
            file: file,
            line: line
        )
    }

    static func assertDeleteRemovesCustomColorsButBuiltInsRemainAvailableAndDefaultFallsBackToWhite(
        using fixture: TagColorRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeTagColorRepository()
        let customID = UUID()
        try repository.upsert(
            TagColorSnapshot(
                id: customID,
                name: "Contract Delete",
                prefix: "CD",
                rgba: RGBAColor(r: 0.8, g: 0.15, b: 0.2)
            )
        )
        try repository.setDefaultColor(id: TagColorDefaults.blueID)

        try repository.deleteColors(ids: [customID])
        var colors = try fixture.makeTagColorRepository().fetchColors()
        XCTAssertFalse(colors.contains { $0.id == customID }, file: file, line: line)
        XCTAssertEqual(defaultColorIDs(in: colors), [TagColorDefaults.blueID], file: file, line: line)

        // A selected built-in may have a persisted override, but deleting that override must not
        // remove the built-in application constant from the visible library.
        try fixture.makeTagColorRepository().deleteColors(ids: [TagColorDefaults.blueID])
        colors = try fixture.makeTagColorRepository().fetchColors()
        XCTAssertTrue(colors.contains { $0.id == TagColorDefaults.blueID }, file: file, line: line)
        XCTAssertEqual(defaultColorIDs(in: colors), [TagColorDefaults.whiteID], file: file, line: line)

        let canonicalBlue = try XCTUnwrap(
            TagColorDefaults.seedDefaultColors().first { $0.id == TagColorDefaults.blueID },
            file: file,
            line: line
        )
        let visibleBlue = try XCTUnwrap(
            colors.first { $0.id == TagColorDefaults.blueID },
            file: file,
            line: line
        )
        assertSameDefinition(visibleBlue, canonicalBlue, file: file, line: line)

        let beforeVirtualDelete = stableProjection(colors)
        try fixture.makeTagColorRepository().deleteColors(ids: [TagColorDefaults.yellowID, UUID()])
        let afterVirtualDelete = stableProjection(try fixture.makeTagColorRepository().fetchColors())
        XCTAssertEqual(
            afterVirtualDelete,
            beforeVirtualDelete,
            "Deleting a nonmaterialized built-in or unknown UUID must not remove visible built-ins.",
            file: file,
            line: line
        )
    }

    static func assertReorderPersistsCompleteLibraryOrder(
        using fixture: TagColorRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeTagColorRepository()

        // Materialize the built-ins through the repository boundary so the contract remains
        // persistence-neutral while still proving durable ordering behavior.
        for color in TagColorDefaults.seedDefaultColors() {
            try repository.upsert(color)
        }

        let custom = TagColorSnapshot(
            id: UUID(),
            name: "Contract Ordered Custom",
            prefix: "COC",
            rgba: RGBAColor(r: 0.2, g: 0.75, b: 0.55)
        )
        try repository.upsert(custom)

        let desiredOrder = [
            TagColorDefaults.blueID,
            custom.id,
            TagColorDefaults.whiteID,
            TagColorDefaults.yellowID,
            TagColorDefaults.redID,
            TagColorDefaults.orangeID,
            TagColorDefaults.greenID,
            TagColorDefaults.purpleID,
            TagColorDefaults.pinkID
        ]

        try repository.reorder(colorIDs: desiredOrder)

        let reloaded = try fixture.makeTagColorRepository().fetchColors()
        XCTAssertEqual(reloaded.map(\.id), desiredOrder, file: file, line: line)
        XCTAssertEqual(
            reloaded.map(\.sortOrder),
            Array(desiredOrder.indices),
            "A complete reorder must persist a contiguous library order.",
            file: file,
            line: line
        )
    }

    static func assertRestoreDefaultsRepairsCanonicalDefinitionsPreservesCustomsAndIsIdempotent(
        using fixture: TagColorRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeTagColorRepository()

        var modifiedYellow = try XCTUnwrap(
            TagColorDefaults.seedDefaultColors().first { $0.id == TagColorDefaults.yellowID },
            file: file,
            line: line
        )
        modifiedYellow.prefix = "ZZ"
        modifiedYellow.rgba = RGBAColor(r: 0.05, g: 0.05, b: 0.05)
        try repository.upsert(modifiedYellow)

        let custom = TagColorSnapshot(
            id: UUID(),
            name: "Contract Preserve",
            prefix: "CP",
            rgba: RGBAColor(r: 0.45, g: 0.15, b: 0.7)
        )
        try repository.upsert(custom)
        try repository.setDefaultColor(id: custom.id)

        try repository.restoreDefaultColors()

        let restored = try fixture.makeTagColorRepository().fetchColors()
        let expectedDefaults = TagColorDefaults.seedDefaultColors()
        for expected in expectedDefaults {
            let actual = try XCTUnwrap(
                restored.first { $0.id == expected.id },
                "Restoring defaults must expose every canonical built-in UUID.",
                file: file,
                line: line
            )
            assertSameDefinition(actual, expected, file: file, line: line)
        }

        let restoredCustom = try XCTUnwrap(
            restored.first { $0.id == custom.id },
            "Restoring built-ins must not delete custom colors.",
            file: file,
            line: line
        )
        XCTAssertEqual(restoredCustom.name, custom.name, file: file, line: line)
        XCTAssertEqual(restoredCustom.prefix, custom.prefix, file: file, line: line)
        XCTAssertEqual(restoredCustom.rgba, custom.rgba, file: file, line: line)
        XCTAssertEqual(defaultColorIDs(in: restored), [custom.id], file: file, line: line)

        let firstRestoreProjection = stableProjection(restored)
        try fixture.makeTagColorRepository().restoreDefaultColors()
        let secondRestoreProjection = stableProjection(try fixture.makeTagColorRepository().fetchColors())
        XCTAssertEqual(
            secondRestoreProjection,
            firstRestoreProjection,
            "Restoring defaults repeatedly must be idempotent at the Domain-visible library boundary.",
            file: file,
            line: line
        )
    }

    static func assertNormalizedNameCollisionKeepsCanonicalIdentityAndRemapsReferences(
        using fixture: TagColorRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeTagColorRepository()
        let canonicalID = UUID()
        let incomingID = UUID()

        try repository.upsert(
            TagColorSnapshot(
                id: canonicalID,
                name: "Contract Merge",
                prefix: "CM",
                rgba: RGBAColor(r: 0.2, g: 0.3, b: 0.4)
            )
        )
        try fixture.referenceControl.seedReferences(incomingID)

        var incoming = TagColorSnapshot(
            id: incomingID,
            name: "Placeholder",
            prefix: "X",
            rgba: RGBAColor(r: 0.75, g: 0.35, b: 0.15),
            isDefault: true
        )
        incoming.name = "  contract merge  "
        incoming.prefix = " new "

        try fixture.makeTagColorRepository().upsert(incoming)

        let reloaded = try fixture.makeTagColorRepository().fetchColors()
        let matching = reloaded.filter {
            TagColorLibraryRules.normalizedNameKey($0.name)
                == TagColorLibraryRules.normalizedNameKey("Contract Merge")
        }
        XCTAssertEqual(matching.count, 1, "Normalized names must remain unique.", file: file, line: line)

        let merged = try XCTUnwrap(matching.first, file: file, line: line)
        XCTAssertEqual(
            merged.id,
            canonicalID,
            "A name collision must retain the existing canonical application UUID.",
            file: file,
            line: line
        )
        XCTAssertEqual(merged.name, "contract merge", file: file, line: line)
        XCTAssertEqual(merged.prefix, "NEW", file: file, line: line)
        XCTAssertEqual(merged.rgba, incoming.rgba, file: file, line: line)
        XCTAssertTrue(merged.isDefault, file: file, line: line)
        XCTAssertFalse(reloaded.contains { $0.id == incomingID }, file: file, line: line)
        XCTAssertEqual(defaultColorIDs(in: reloaded), [canonicalID], file: file, line: line)

        XCTAssertEqual(
            try fixture.referenceControl.fetchReferences(),
            TagColorReferenceSnapshot(
                animalTagColorID: canonicalID,
                historicalTagColorID: canonicalID,
                fieldCheckRosterTagColorID: canonicalID
            ),
            "Merging duplicate tag-color identities must remap every persisted UUID reference.",
            file: file,
            line: line
        )
    }

    private struct StableColorProjection: Equatable {
        let id: UUID
        let name: String
        let prefix: String
        let rgba: RGBAColor
        let sortOrder: Int
        let isDefault: Bool
    }

    private static func stableProjection(_ colors: [TagColorSnapshot]) -> [StableColorProjection] {
        colors.map {
            StableColorProjection(
                id: $0.id,
                name: $0.name,
                prefix: $0.prefix,
                rgba: $0.rgba,
                sortOrder: $0.sortOrder,
                isDefault: $0.isDefault
            )
        }
    }

    private static func requireColor(
        id: UUID,
        in repository: any TagColorRepository,
        file: StaticString,
        line: UInt
    ) throws -> TagColorSnapshot {
        try XCTUnwrap(
            repository.fetchColors().first { $0.id == id },
            "Expected tag color \(id) to be visible after reload.",
            file: file,
            line: line
        )
    }

    private static func defaultColorIDs(in colors: [TagColorSnapshot]) -> [UUID] {
        colors.filter(\.isDefault).map(\.id)
    }

    private static func assertSameDefinition(
        _ actual: TagColorSnapshot,
        _ expected: TagColorSnapshot,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.id, expected.id, file: file, line: line)
        XCTAssertEqual(actual.name, expected.name, file: file, line: line)
        XCTAssertEqual(actual.prefix, expected.prefix, file: file, line: line)
        XCTAssertEqual(actual.rgba, expected.rgba, file: file, line: line)
    }

    private static func fixedDate(_ secondsSince1970: TimeInterval) -> Date {
        Date(timeIntervalSince1970: secondsSince1970)
    }
}
