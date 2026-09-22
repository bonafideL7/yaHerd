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
    let fieldCheckDamRosterTagColorID: UUID?
    let fieldCheckFindingTagColorIDSnapshot: UUID?
    let workingQueueTagColorIDSnapshot: UUID?
    let workingQueueDamTagColorIDSnapshot: UUID?
}

/// Target-only hooks used to establish and inspect tag-color UUID references.
///
/// A Core Data contract runner should seed representative records for every persisted tag-color
/// reference category and return their current UUID values after repository mutations.
@MainActor
struct TagColorReferenceTestControl {
    /// Seeds a physical color row directly through test persistence infrastructure. This bypasses
    /// repository name reconciliation so a runner can establish duplicate physical rows deliberately
    /// and then prove the repository repairs them through application UUID semantics.
    let seedPersistedColor: (_ color: TagColorSnapshot) throws -> Void
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
    let herdSelectionControl: HerdRepositorySelectionTestControl
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

        var incoming = TagColorSnapshot(
            id: incomingID,
            name: "Placeholder",
            prefix: "X",
            rgba: RGBAColor(r: 0.75, g: 0.35, b: 0.15),
            sortOrder: 99,
            isDefault: true
        )
        incoming.name = "  contract merge  "
        incoming.prefix = " new "

        // Seed the duplicate through target-only persistence control so references point at a real
        // physical color row before the repository is asked to reconcile the name collision.
        try fixture.referenceControl.seedPersistedColor(incoming)
        try fixture.referenceControl.seedReferences(incomingID)

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
                fieldCheckRosterTagColorID: canonicalID,
                fieldCheckDamRosterTagColorID: canonicalID,
                fieldCheckFindingTagColorIDSnapshot: canonicalID,
                workingQueueTagColorIDSnapshot: canonicalID,
                workingQueueDamTagColorIDSnapshot: canonicalID
            ),
            "Merging duplicate tag-color identities must remap every persisted UUID reference.",
            file: file,
            line: line
        )
    }

    static func assertBuiltInNameCollisionPreservesBuiltInIdentityAndRemapsReferences(
        using fixture: TagColorRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let incomingID = UUID()
        var incoming = TagColorSnapshot(
            id: incomingID,
            name: "Placeholder",
            prefix: "X",
            rgba: RGBAColor(r: 0.1, g: 0.25, b: 0.85),
            sortOrder: 99
        )
        incoming.name = "  blue  "
        incoming.prefix = " custom-blue "

        // Built-ins are application constants even when no physical row exists yet. Seed a
        // conflicting persisted row so the repository must reconcile the duplicate against the
        // stable built-in application UUID instead of allowing the custom UUID to replace Blue.
        try fixture.referenceControl.seedPersistedColor(incoming)
        try fixture.referenceControl.seedReferences(incomingID)

        try fixture.makeTagColorRepository().upsert(incoming)

        let reloaded = try fixture.makeTagColorRepository().fetchColors()
        let matching = reloaded.filter {
            TagColorLibraryRules.normalizedNameKey($0.name)
                == TagColorLibraryRules.normalizedNameKey("Blue")
        }
        XCTAssertEqual(matching.count, 1, "A built-in normalized name must remain unique.", file: file, line: line)

        let merged = try XCTUnwrap(matching.first, file: file, line: line)
        XCTAssertEqual(
            merged.id,
            TagColorDefaults.blueID,
            "A normalized-name collision with a built-in must preserve the built-in application UUID.",
            file: file,
            line: line
        )
        XCTAssertEqual(merged.name, "blue", file: file, line: line)
        XCTAssertEqual(merged.prefix, "CUSTOM-BLUE", file: file, line: line)
        XCTAssertEqual(merged.rgba, incoming.rgba, file: file, line: line)
        XCTAssertFalse(reloaded.contains { $0.id == incomingID }, file: file, line: line)

        XCTAssertEqual(
            try fixture.referenceControl.fetchReferences(),
            TagColorReferenceSnapshot(
                animalTagColorID: TagColorDefaults.blueID,
                historicalTagColorID: TagColorDefaults.blueID,
                fieldCheckRosterTagColorID: TagColorDefaults.blueID,
                fieldCheckDamRosterTagColorID: TagColorDefaults.blueID,
                fieldCheckFindingTagColorIDSnapshot: TagColorDefaults.blueID,
                workingQueueTagColorIDSnapshot: TagColorDefaults.blueID,
                workingQueueDamTagColorIDSnapshot: TagColorDefaults.blueID
            ),
            "Built-in collision repair must remap every persisted UUID reference to the stable built-in identity.",
            file: file,
            line: line
        )
    }

    static func assertReferencedCustomColorRemovalPreservesHistoricalReferenceIdentity(
        using fixture: TagColorRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repository = fixture.makeTagColorRepository()
        let colorID = UUID()
        let color = TagColorSnapshot(
            id: colorID,
            name: "Contract Historical Color",
            prefix: "CHC",
            rgba: RGBAColor(r: 0.35, g: 0.55, b: 0.75)
        )

        try repository.upsert(color)
        try fixture.referenceControl.seedReferences(colorID)
        try repository.deleteColors(ids: [colorID])

        XCTAssertFalse(
            try fixture.makeTagColorRepository().fetchColors().contains { $0.id == colorID },
            "Removing a custom color must remove it from the visible library.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.referenceControl.fetchReferences(),
            TagColorReferenceSnapshot(
                animalTagColorID: colorID,
                historicalTagColorID: colorID,
                fieldCheckRosterTagColorID: colorID,
                fieldCheckDamRosterTagColorID: colorID,
                fieldCheckFindingTagColorIDSnapshot: colorID,
                workingQueueTagColorIDSnapshot: colorID,
                workingQueueDamTagColorIDSnapshot: colorID
            ),
            "Removing a visible tag color must not rewrite or nullify persisted historical color identity.",
            file: file,
            line: line
        )
    }

    static func assertReadsWritesDefaultsAndNameUniquenessAreHerdScoped(
        using fixture: TagColorRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let firstHerdID = UUID()
        let secondHerdID = UUID()
        try fixture.herdSelectionControl.seedHerd(
            firstHerdID,
            "Tag Color Contract Herd A",
            fixedDate(1_710_000_000),
            fixedDate(1_710_000_100)
        )
        try fixture.herdSelectionControl.seedHerd(
            secondHerdID,
            "Tag Color Contract Herd B",
            fixedDate(1_720_000_000),
            fixedDate(1_720_000_100)
        )

        let firstColorID = UUID()
        let secondColorID = UUID()

        try fixture.herdSelectionControl.setCurrentHerdID(firstHerdID)
        try fixture.makeTagColorRepository().upsert(
            TagColorSnapshot(
                id: firstColorID,
                name: "Scoped Contract Color",
                prefix: "A",
                rgba: RGBAColor(r: 0.15, g: 0.45, b: 0.75)
            )
        )
        try fixture.makeTagColorRepository().setDefaultColor(id: firstColorID)

        try fixture.herdSelectionControl.setCurrentHerdID(secondHerdID)
        let secondBeforeWrite = try fixture.makeTagColorRepository().fetchColors()
        XCTAssertFalse(secondBeforeWrite.contains { $0.id == firstColorID }, file: file, line: line)
        XCTAssertEqual(
            defaultColorIDs(in: secondBeforeWrite),
            [TagColorDefaults.whiteID],
            "A default preference selected in another Herd must not leak into the current Herd.",
            file: file,
            line: line
        )

        var secondColor = TagColorSnapshot(
            id: secondColorID,
            name: "Placeholder",
            prefix: "B",
            rgba: RGBAColor(r: 0.75, g: 0.45, b: 0.15)
        )
        secondColor.name = "  scoped contract color  "
        try fixture.makeTagColorRepository().upsert(secondColor)
        try fixture.makeTagColorRepository().setDefaultColor(id: secondColorID)

        let secondReloaded = try fixture.makeTagColorRepository().fetchColors()
        XCTAssertTrue(secondReloaded.contains { $0.id == secondColorID }, file: file, line: line)
        XCTAssertFalse(secondReloaded.contains { $0.id == firstColorID }, file: file, line: line)
        XCTAssertEqual(defaultColorIDs(in: secondReloaded), [secondColorID], file: file, line: line)

        try fixture.herdSelectionControl.setCurrentHerdID(firstHerdID)
        let firstReloaded = try fixture.makeTagColorRepository().fetchColors()
        XCTAssertTrue(firstReloaded.contains { $0.id == firstColorID }, file: file, line: line)
        XCTAssertFalse(firstReloaded.contains { $0.id == secondColorID }, file: file, line: line)
        XCTAssertEqual(defaultColorIDs(in: firstReloaded), [firstColorID], file: file, line: line)

        let firstScopedColor = try XCTUnwrap(
            firstReloaded.first { $0.id == firstColorID },
            file: file,
            line: line
        )
        XCTAssertEqual(firstScopedColor.name, "Scoped Contract Color", file: file, line: line)

        try fixture.herdSelectionControl.setCurrentHerdID(secondHerdID)
        let secondScopedColor = try XCTUnwrap(
            fixture.makeTagColorRepository().fetchColors().first { $0.id == secondColorID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            TagColorLibraryRules.normalizedNameKey(secondScopedColor.name),
            TagColorLibraryRules.normalizedNameKey(firstScopedColor.name),
            "Normalized-name uniqueness is scoped to a Herd, not global across Herd workspaces.",
            file: file,
            line: line
        )

        // Capture Herd A as the unrelated control, then exercise every remaining library mutation
        // from Herd B. Returning to Herd A must reproduce the same Domain-visible library exactly.
        try fixture.herdSelectionControl.setCurrentHerdID(firstHerdID)
        for builtIn in TagColorDefaults.seedDefaultColors() {
            try fixture.makeTagColorRepository().upsert(builtIn)
        }
        let firstControlProjection = stableProjection(try fixture.makeTagColorRepository().fetchColors())

        try fixture.herdSelectionControl.setCurrentHerdID(secondHerdID)
        for builtIn in TagColorDefaults.seedDefaultColors() {
            try fixture.makeTagColorRepository().upsert(builtIn)
        }
        let secondExtraID = UUID()
        try fixture.makeTagColorRepository().upsert(
            TagColorSnapshot(
                id: secondExtraID,
                name: "Second Herd Disposable",
                prefix: "SHD",
                rgba: RGBAColor(r: 0.55, g: 0.25, b: 0.65)
            )
        )

        let secondVisibleIDs = try fixture.makeTagColorRepository().fetchColors().map(\.id)
        let reorderedSecondIDs = [secondColorID]
            + secondVisibleIDs.filter { $0 != secondColorID && $0 != secondExtraID }
            + [secondExtraID]
        try fixture.makeTagColorRepository().reorder(colorIDs: reorderedSecondIDs)
        try fixture.makeTagColorRepository().deleteColors(ids: [secondExtraID])
        try fixture.makeTagColorRepository().restoreDefaultColors()

        try fixture.herdSelectionControl.setCurrentHerdID(firstHerdID)
        XCTAssertEqual(
            stableProjection(try fixture.makeTagColorRepository().fetchColors()),
            firstControlProjection,
            "Upsert, default selection, reorder, delete, and restore in another Herd must leave the unrelated Herd unchanged.",
            file: file,
            line: line
        )
    }

    static func assertMissingOrStaleCurrentHerdDoesNotFallbackOrBootstrapOnReadOrWrite(
        using fixture: TagColorRepositoryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let storedHerdID = UUID()
        try fixture.herdSelectionControl.seedHerd(
            storedHerdID,
            "Stored Tag Color Contract Herd",
            fixedDate(1_730_000_000),
            fixedDate(1_730_000_100)
        )
        try fixture.herdSelectionControl.setCurrentHerdID(storedHerdID)

        let existingColorID = UUID()
        try fixture.makeTagColorRepository().upsert(
            TagColorSnapshot(
                id: existingColorID,
                name: "Existing Scoped Color",
                prefix: "ESC",
                rgba: RGBAColor(r: 0.2, g: 0.5, b: 0.7)
            )
        )

        let herdRowsBeforeFailure = try fixture.herdSelectionControl.persistedHerdRowCountsByID()
        let staleColorID = UUID()
        try fixture.herdSelectionControl.setCurrentHerdID(UUID())

        XCTAssertThrowsError(
            try fixture.makeTagColorRepository().fetchColors(),
            "A stale current-Herd UUID must reject a Herd-owned tag-color read.",
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeTagColorRepository().upsert(
                TagColorSnapshot(
                    id: staleColorID,
                    name: "Must Not Fall Back",
                    prefix: "MNFB",
                    rgba: RGBAColor(r: 0.7, g: 0.2, b: 0.5)
                )
            ),
            "A stale current-Herd UUID must reject a Herd-owned tag-color write.",
            file: file,
            line: line
        )

        let missingColorID = UUID()
        try fixture.herdSelectionControl.setCurrentHerdID(nil)

        XCTAssertThrowsError(
            try fixture.makeTagColorRepository().fetchColors(),
            "A missing current-Herd selection must reject a Herd-owned tag-color read.",
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try fixture.makeTagColorRepository().upsert(
                TagColorSnapshot(
                    id: missingColorID,
                    name: "Must Not Bootstrap",
                    prefix: "MNB",
                    rgba: RGBAColor(r: 0.5, g: 0.7, b: 0.2)
                )
            ),
            "A missing current-Herd selection must reject a Herd-owned tag-color write.",
            file: file,
            line: line
        )

        XCTAssertEqual(
            try fixture.herdSelectionControl.persistedHerdRowCountsByID(),
            herdRowsBeforeFailure,
            "Failed tag-color writes must not create or duplicate Herd roots.",
            file: file,
            line: line
        )

        try fixture.herdSelectionControl.setCurrentHerdID(storedHerdID)
        let storedHerdColors = try fixture.makeTagColorRepository().fetchColors()
        XCTAssertTrue(storedHerdColors.contains { $0.id == existingColorID }, file: file, line: line)
        XCTAssertFalse(storedHerdColors.contains { $0.id == staleColorID }, file: file, line: line)
        XCTAssertFalse(storedHerdColors.contains { $0.id == missingColorID }, file: file, line: line)
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
