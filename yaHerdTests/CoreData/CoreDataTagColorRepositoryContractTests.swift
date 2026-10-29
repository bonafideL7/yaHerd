@preconcurrency import CoreData
import Foundation
import XCTest
@testable import yaHerd

/// M11 Core Data runner for the permanent persistence-neutral Tag Color
/// contracts, including physical CDAnimalTag, Field Check and Working reference
/// mutations. UI edit/picker behavior and failed-save rollback have separate owners.
@MainActor
final class CoreDataTagColorRepositoryContractTests: XCTestCase {
    func testBuiltInLibraryHasStableIdentityOrderingAndWhiteDefault() async throws {
        try await run {
            try TagColorRepositoryContract
                .assertBuiltInLibraryHasStableIdentityOrderingAndWhiteDefault(using: $0)
        }
    }

    func testUpsertNormalizesPersistsAndPreservesApplicationIdentity() async throws {
        try await run {
            try TagColorRepositoryContract
                .assertUpsertNormalizesPersistsAndPreservesApplicationIdentity(using: $0)
        }
    }

    func testEmptyNameUpsertIsNoOp() async throws {
        try await run {
            try TagColorRepositoryContract.assertEmptyNameUpsertIsNoOp(using: $0)
        }
    }

    func testDefaultSelectionIsExclusivePersistentAndUnaffectedByUnknownIDs() async throws {
        try await run {
            try TagColorRepositoryContract
                .assertDefaultSelectionIsExclusivePersistentAndUnaffectedByUnknownIDs(using: $0)
        }
    }

    func testDeleteRemovesCustomColorsButBuiltInsRemainAvailable() async throws {
        try await run {
            try TagColorRepositoryContract
                .assertDeleteRemovesCustomColorsButBuiltInsRemainAvailableAndDefaultFallsBackToWhite(
                    using: $0
                )
        }
    }

    func testReorderPersistsCompleteLibraryOrder() async throws {
        try await run {
            try TagColorRepositoryContract.assertReorderPersistsCompleteLibraryOrder(using: $0)
        }
    }

    func testRestoreDefaultsRepairsCanonicalDefinitionsPreservesCustomsAndIsIdempotent() async throws {
        try await run {
            try TagColorRepositoryContract
                .assertRestoreDefaultsRepairsCanonicalDefinitionsPreservesCustomsAndIsIdempotent(
                    using: $0
                )
        }
    }

    func testReadsWritesDefaultsAndNameUniquenessAreHerdScoped() async throws {
        try await run {
            try TagColorRepositoryContract
                .assertReadsWritesDefaultsAndNameUniquenessAreHerdScoped(using: $0)
        }
    }

    func testMissingOrStaleCurrentHerdDoesNotFallbackOrBootstrap() async throws {
        try await run {
            try TagColorRepositoryContract
                .assertMissingOrStaleCurrentHerdDoesNotFallbackOrBootstrapOnReadOrWrite(using: $0)
        }
    }


    func testCustomColorCollisionRemapsAllPersistedReferenceCategories() async throws {
        try await run {
            try TagColorRepositoryContract
                .assertNormalizedNameCollisionKeepsCanonicalIdentityAndRemapsReferences(using: $0)
        }
    }

    func testBuiltInColorCollisionPreservesCanonicalIDAcrossPersistedReferences() async throws {
        try await run {
            try TagColorRepositoryContract
                .assertBuiltInNameCollisionPreservesBuiltInIdentityAndRemapsReferences(using: $0)
        }
    }

    func testReferencedCustomColorRemovalPreservesHistoricalLookupAndUUIDs() async throws {
        try await run {
            try TagColorRepositoryContract
                .assertReferencedCustomColorRemovalPreservesHistoricalReferenceIdentity(using: $0)
        }
    }

    func testMissingImportedTagAnimalRejectsColorRemapAndRollsBack() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let environment = CoreDataTagColorContractEnvironment(assembly: assembly)
        try environment.seedInitialHerd()
        let repository = environment.fixture.makeTagColorRepository()

        let original = TagColorSnapshot(
            name: "Before Remap Amber",
            prefix: "BRA",
            rgba: RGBAColor(r: 0.8, g: 0.5, b: 0.2)
        )
        let collision = TagColorSnapshot(
            name: "Remap Target Blue",
            prefix: "RTB",
            rgba: RGBAColor(r: 0.2, g: 0.3, b: 0.8)
        )
        try repository.upsert(original)
        try repository.upsert(collision)

        // CloudKit may import the Tag before its owning Animal. Its Herd and
        // Color exist, but its optional Animal relationship has not arrived.
        let tagID = UUID()
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = try XCTUnwrap(CoreDataLookup().herd(
                id: environment.initialHerdID, in: context
            ))
            let color = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDTagColorDefinition.self,
                id: collision.id,
                herdID: environment.initialHerdID,
                in: context
            ))
            let tag = CDAnimalTag(context: context)
            tag.id = tagID
            tag.number = "Unlinked"
            tag.isPrimary = false
            tag.isActive = false
            tag.assignedAt = Date(timeIntervalSince1970: 100)
            tag.removedAt = Date(timeIntervalSince1970: 200)
            tag.herd = herd
            tag.color = color
            XCTAssertNil(tag.animal)
            try context.save()
        }

        var renamed = original
        renamed.name = collision.name
        XCTAssertThrowsError(try repository.upsert(renamed)) {
            XCTAssertEqual(
                $0 as? CoreDataTagColorRepositoryError,
                .missingTagAnimal(tagID: tagID)
            )
        }

        XCTAssertEqual(try repository.fetchColor(id: original.id)?.name, original.name)
        XCTAssertEqual(try repository.fetchColor(id: collision.id)?.name, collision.name)
        let inspection = assembly.contextFactory.makeReadContext()
        try inspection.performAndWait {
            let tag = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDAnimalTag.self,
                id: tagID,
                herdID: environment.initialHerdID,
                in: inspection
            ))
            XCTAssertNil(tag.animal)
            XCTAssertEqual(tag.color?.id, collision.id)
        }
    }

    func testHiddenReferencedCurrentAnimalColorResolvesThroughRealStore() async throws {
        try await run { fixture in
            let originalColorID = UUID()
            let original = TagColorSnapshot(
                id: originalColorID,
                name: "Hidden Current Teal",
                prefix: "HCT",
                rgba: RGBAColor(r: 0.2, g: 0.55, b: 0.6)
            )
            try fixture.makeTagColorRepository().upsert(original)
            try fixture.referenceControl.seedReferences(originalColorID)
            try fixture.makeTagColorRepository().deleteColors(ids: [originalColorID])

            let store = TagColorLibraryStore(repository: fixture.makeTagColorRepository())
            XCTAssertFalse(store.colors.contains { $0.id == originalColorID })

            let definition = try XCTUnwrap(store.definition(for: originalColorID))
            XCTAssertEqual(definition.id, originalColorID)
            XCTAssertEqual(definition.name, original.name)
            XCTAssertEqual(definition.prefix, original.prefix)
            XCTAssertEqual(definition.rgba, original.rgba)
            XCTAssertEqual(store.resolvedColorID(originalColorID), originalColorID)
            XCTAssertEqual(store.resolvedDefinition(tagColorID: originalColorID).id, originalColorID)
            XCTAssertEqual(store.formattedTag(tagNumber: "31", colorID: originalColorID), "HCT31")

            let physical = try fixture.referenceControl.fetchReferences()
            XCTAssertEqual(physical.animalTagColorID, originalColorID)
            XCTAssertEqual(physical.historicalTagColorID, originalColorID)
            XCTAssertEqual(physical.fieldCheckRosterTagColorID, originalColorID)
            XCTAssertEqual(physical.workingQueueTagColorIDSnapshot, originalColorID)
        }
    }


    /// The user-facing TagColorLibraryStore behavior previously covered only
    /// by a SwiftData ModelContext test now runs against the active Core Data
    /// app persistence stack. A pristine read must never create physical rows.
    func testTagColorLibraryStoreStartsWithVirtualWhiteWithoutWriting() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let environment = CoreDataTagColorContractEnvironment(assembly: assembly)
        try environment.seedInitialHerd()

        let initialCount = try physicalColorRowCount(in: assembly)
        XCTAssertEqual(initialCount, 0)

        let store = TagColorLibraryStore(repository: environment.fixture.makeTagColorRepository())
        XCTAssertEqual(store.defaultColor.id, TagColorDefaults.whiteID)
        XCTAssertEqual(store.defaultColor.name, "White")
        XCTAssertEqual(store.defaultColorID, TagColorDefaults.whiteID)
        XCTAssertEqual(store.resolvedColorID(nil), TagColorDefaults.whiteID)
        XCTAssertEqual(store.editableColorID(nil), TagColorDefaults.whiteID)
        XCTAssertNil(store.lastErrorMessage)

        let reloaded = TagColorLibraryStore(
            repository: environment.fixture.makeTagColorRepository()
        )
        XCTAssertEqual(reloaded.defaultColor.id, TagColorDefaults.whiteID)
        XCTAssertEqual(reloaded.colors.map(\.id), store.colors.map(\.id))
        XCTAssertEqual(
            try physicalColorRowCount(in: assembly),
            initialCount,
            "Passive Tag Color library loading must not materialize defaults or mutate persistence."
        )
    }

    func testTagColorLibraryStoreSelectsExactlyOnePersistedDefaultAndReloads() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let environment = CoreDataTagColorContractEnvironment(assembly: assembly)
        try environment.seedInitialHerd()

        let store = TagColorLibraryStore(repository: environment.fixture.makeTagColorRepository())
        let blue = try XCTUnwrap(store.colors.first { $0.id == TagColorDefaults.blueID })
        store.setDefaultColor(id: blue.id)

        XCTAssertNil(store.lastErrorMessage)
        XCTAssertEqual(store.defaultColor.id, blue.id)
        XCTAssertEqual(store.defaultColorID, blue.id)
        XCTAssertEqual(store.resolvedColorID(nil), blue.id)
        XCTAssertEqual(store.colors.filter(\.isDefault).map(\.id), [blue.id])

        let fresh = TagColorLibraryStore(
            repository: environment.fixture.makeTagColorRepository()
        )
        XCTAssertEqual(fresh.defaultColor.id, blue.id)
        XCTAssertEqual(fresh.resolvedColorID(nil), blue.id)
        XCTAssertEqual(fresh.colors.filter(\.isDefault).map(\.id), [blue.id])

        let context = assembly.contextFactory.makeReadContext()
        let physicalDefaultIDs: [UUID] = try context.performAndWait {
            let request = NSFetchRequest<CDTagColorDefinition>(
                entityName: CDTagColorDefinition.coreDataEntityName
            )
            return try context.fetch(request).filter(\.isDefault).map(\.id)
        }
        XCTAssertEqual(
            physicalDefaultIDs,
            [blue.id],
            "The selected UI default must be the sole committed physical Core Data default."
        )
    }

    func testCanonicalTagColorPaletteExcludesRetiredBuiltInColors() {
        let names = Set(TagColorDefaults.seedDefaultColors().map(\.name))
        XCTAssertFalse(names.contains("Black"))
        XCTAssertFalse(names.contains("Brown"))
        XCTAssertFalse(names.contains("Gray"))
    }

    private func physicalColorRowCount(
        in assembly: CoreDataPersistenceAssembly
    ) throws -> Int {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let request = NSFetchRequest<CDTagColorDefinition>(
                entityName: CDTagColorDefinition.coreDataEntityName
            )
            return try context.count(for: request)
        }
    }

    func testStagedCustomInsertionAndUpdateFailuresRollbackAndRetry() async throws {
        try await runRollback { environment in
            let normal = environment.fixture.makeTagColorRepository()
            let inserted = TagColorSnapshot(
                name: "Rollback Canary",
                prefix: "RBC",
                rgba: RGBAColor(r: 0.15, g: 0.55, b: 0.7)
            )
            let baseline = try normal.fetchColors()
            let probe = CoreDataTagColorRollbackProbe()
            let failing = environment.makeFaultInjectingRepository(probe)

            XCTAssertThrowsError(try failing.upsert(inserted)) {
                XCTAssertEqual($0 as? CoreDataTagColorInjectedFailure, .afterStaging)
            }
            try probe.assertContextRolledBack()
            XCTAssertEqual(try normal.fetchColors(), baseline)
            XCTAssertNil(try normal.fetchColor(id: inserted.id))
            try failing.upsert(inserted)
            XCTAssertEqual(try normal.fetchColor(id: inserted.id)?.id, inserted.id)
        }

        try await runRollback { environment in
            let normal = environment.fixture.makeTagColorRepository()
            let original = TagColorSnapshot(
                name: "Rollback Original",
                prefix: "RBO",
                rgba: RGBAColor(r: 0.2, g: 0.4, b: 0.6)
            )
            try normal.upsert(original)
            let baseline = try normal.fetchColors()
            let baselinePhysical = try XCTUnwrap(normal.fetchColor(id: original.id))
            let changed = TagColorSnapshot(
                id: original.id,
                name: "Rollback Updated",
                prefix: "RBU",
                rgba: RGBAColor(r: 0.8, g: 0.5, b: 0.3),
                isDefault: true
            )
            let probe = CoreDataTagColorRollbackProbe()
            let failing = environment.makeFaultInjectingRepository(probe)

            XCTAssertThrowsError(try failing.upsert(changed)) {
                XCTAssertEqual($0 as? CoreDataTagColorInjectedFailure, .afterStaging)
            }
            try probe.assertContextRolledBack()
            XCTAssertEqual(try normal.fetchColors(), baseline)
            XCTAssertEqual(try normal.fetchColor(id: original.id), baselinePhysical)
            try failing.upsert(changed)
            XCTAssertEqual(try normal.fetchColor(id: original.id)?.name, "Rollback Updated")
        }
    }

    func testStagedDefaultAndReorderFailuresRollbackAndRetry() async throws {
        try await runRollback { environment in
            let normal = environment.fixture.makeTagColorRepository()
            let baseline = try normal.fetchColors()
            let previousDefaultID = try XCTUnwrap(baseline.first(where: \.isDefault)?.id)
            let blue = try XCTUnwrap(baseline.first { $0.name == "Blue" })
            XCTAssertNotEqual(previousDefaultID, blue.id)
            let probe = CoreDataTagColorRollbackProbe()
            let failing = environment.makeFaultInjectingRepository(probe)

            XCTAssertThrowsError(try failing.setDefaultColor(id: blue.id)) {
                XCTAssertEqual($0 as? CoreDataTagColorInjectedFailure, .afterStaging)
            }
            try probe.assertContextRolledBack()
            XCTAssertEqual(try normal.fetchColors(), baseline)
            XCTAssertEqual(
                try normal.fetchColors().filter(\.isDefault).map(\.id),
                [previousDefaultID],
                "Failed default reassignment must restore the original default."
            )

            try failing.setDefaultColor(id: blue.id)
            XCTAssertEqual(
                try normal.fetchColors().filter(\.isDefault).map(\.id),
                [blue.id],
                "Successful reassignment must select Blue and clear the previous default."
            )
        }

        try await runRollback { environment in
            let normal = environment.fixture.makeTagColorRepository()
            let a = TagColorSnapshot(
                name: "Reorder One", prefix: "RO1",
                rgba: RGBAColor(r: 0.2, g: 0.6, b: 0.8)
            )
            let b = TagColorSnapshot(
                name: "Reorder Two", prefix: "RO2",
                rgba: RGBAColor(r: 0.7, g: 0.5, b: 0.3)
            )
            try normal.upsert(a)
            try normal.upsert(b)
            let baseline = try normal.fetchColors()
            let order = [b.id, a.id] + baseline.map(\.id).filter { $0 != a.id && $0 != b.id }
            let probe = CoreDataTagColorRollbackProbe()
            let failing = environment.makeFaultInjectingRepository(probe)

            XCTAssertThrowsError(try failing.reorder(colorIDs: order)) {
                XCTAssertEqual($0 as? CoreDataTagColorInjectedFailure, .afterStaging)
            }
            try probe.assertContextRolledBack()
            XCTAssertEqual(try normal.fetchColors(), baseline)
            try failing.reorder(colorIDs: order)
            XCTAssertNotEqual(try normal.fetchColors(), baseline)
        }
    }

    func testStagedReferencedHideAndDefaultRestoreFailuresRollbackAndRetry() async throws {
        try await runRollback { environment in
            let fixture = environment.fixture
            let normal = fixture.makeTagColorRepository()
            let original = TagColorSnapshot(
                name: "Referenced Rollback",
                prefix: "RBR",
                rgba: RGBAColor(r: 0.45, g: 0.2, b: 0.8)
            )
            try normal.upsert(original)
            try fixture.referenceControl.seedReferences(original.id)
            let baseline = try normal.fetchColors()
            let originalDefinition = try XCTUnwrap(normal.fetchColor(id: original.id))
            let referencesBefore = try fixture.referenceControl.fetchReferences()
            let probe = CoreDataTagColorRollbackProbe()
            let failing = environment.makeFaultInjectingRepository(probe)

            XCTAssertThrowsError(try failing.deleteColors(ids: [original.id])) {
                XCTAssertEqual($0 as? CoreDataTagColorInjectedFailure, .afterStaging)
            }
            try probe.assertContextRolledBack()
            XCTAssertEqual(try normal.fetchColors(), baseline)
            XCTAssertEqual(try normal.fetchColor(id: original.id), originalDefinition)
            XCTAssertEqual(try fixture.referenceControl.fetchReferences(), referencesBefore)
            try failing.deleteColors(ids: [original.id])
            XCTAssertFalse(try normal.fetchColors().contains { $0.id == original.id })
            XCTAssertEqual(try normal.fetchColor(id: original.id)?.id, original.id)
            XCTAssertEqual(try fixture.referenceControl.fetchReferences(), referencesBefore)
        }

        try await runRollback { environment in
            let normal = environment.fixture.makeTagColorRepository()
            let baseline = try normal.fetchColors()
            let probe = CoreDataTagColorRollbackProbe()
            let failing = environment.makeFaultInjectingRepository(probe)

            XCTAssertThrowsError(try failing.restoreDefaultColors()) {
                XCTAssertEqual($0 as? CoreDataTagColorInjectedFailure, .afterStaging)
            }
            try probe.assertContextRolledBack()
            XCTAssertEqual(try normal.fetchColors(), baseline)
            try failing.restoreDefaultColors()
            XCTAssertEqual(
                try normal.fetchColors().filter(\.isDefault).count,
                1
            )
        }
    }

    func testStagedCustomIdentityMergeFailureRestoresAllSevenReferences() async throws {
        try await runRollback { environment in
            let fixture = environment.fixture
            let original = TagColorSnapshot(
                name: "Collision Canonical",
                prefix: "CC",
                rgba: RGBAColor(r: 0.2, g: 0.3, b: 0.8)
            )
            let incoming = TagColorSnapshot(
                name: "Collision Incoming",
                prefix: "CI",
                rgba: RGBAColor(r: 0.9, g: 0.3, b: 0.4)
            )
            try fixture.referenceControl.seedPersistedColor(original)
            try fixture.referenceControl.seedPersistedColor(incoming)
            try fixture.referenceControl.seedReferences(incoming.id)
            let normal = fixture.makeTagColorRepository()
            let baseline = try normal.fetchColors()
            let originalPhysical = try XCTUnwrap(normal.fetchColor(id: original.id))
            let incomingPhysical = try XCTUnwrap(normal.fetchColor(id: incoming.id))
            let originalReferences = try fixture.referenceControl.fetchReferences()
            let originalRevision = try environment.fetchReferenceAnimalRevision()
            let probe = CoreDataTagColorRollbackProbe(
                expectedRemap: (
                    sourceID: incoming.id,
                    targetID: original.id,
                    originalAnimalRevision: originalRevision
                )
            )
            let failing = environment.makeFaultInjectingRepository(probe)
            let reconciled = TagColorSnapshot(
                id: incoming.id,
                name: original.name,
                prefix: "MER",
                rgba: RGBAColor(r: 0.4, g: 0.6, b: 0.9)
            )

            XCTAssertThrowsError(try failing.upsert(reconciled)) {
                XCTAssertEqual($0 as? CoreDataTagColorInjectedFailure, .afterStaging)
            }
            try probe.assertContextRolledBack()
            XCTAssertEqual(try normal.fetchColors(), baseline)
            XCTAssertEqual(try normal.fetchColor(id: original.id), originalPhysical)
            XCTAssertEqual(try normal.fetchColor(id: incoming.id), incomingPhysical)
            XCTAssertEqual(try fixture.referenceControl.fetchReferences(), originalReferences)
            XCTAssertEqual(try environment.fetchReferenceAnimalRevision(), originalRevision)

            try failing.upsert(reconciled)
            XCTAssertEqual(try fixture.referenceControl.fetchReferences().animalTagColorID, original.id)
            XCTAssertNil(try normal.fetchColor(id: incoming.id))
            XCTAssertNotEqual(
                try environment.fetchReferenceAnimalRevision(), originalRevision,
                "Successful collision repair must rotate the affected Animal's editor revision."
            )
        }
    }


    func testStagedBuiltInIdentityMergeFailureRestoresCanonicalAndPhysicalReferences() async throws {
        try await runRollback { environment in
            let fixture = environment.fixture
            let original = TagColorSnapshot(
                name: "Blue",
                prefix: "CBB",
                rgba: RGBAColor(r: 0.1, g: 0.35, b: 0.7)
            )
            try fixture.referenceControl.seedPersistedColor(original)
            try fixture.referenceControl.seedReferences(original.id)
            let normal = fixture.makeTagColorRepository()
            let baseline = try normal.fetchColors()
            let originalPhysical = try XCTUnwrap(normal.fetchColor(id: original.id))
            let originalReferences = try fixture.referenceControl.fetchReferences()
            let originalRevision = try environment.fetchReferenceAnimalRevision()
            let blue = TagColorSnapshot(
                id: TagColorDefaults.blueID,
                name: "Blue",
                prefix: "B",
                rgba: RGBAColor(r: 0.1, g: 0.2, b: 0.95)
            )
            let probe = CoreDataTagColorRollbackProbe(
                expectedRemap: (
                    sourceID: original.id,
                    targetID: TagColorDefaults.blueID,
                    originalAnimalRevision: originalRevision
                )
            )
            let failing = environment.makeFaultInjectingRepository(probe)

            XCTAssertThrowsError(try failing.upsert(blue)) {
                XCTAssertEqual($0 as? CoreDataTagColorInjectedFailure, .afterStaging)
            }
            try probe.assertContextRolledBack()
            XCTAssertEqual(try normal.fetchColors(), baseline)
            XCTAssertEqual(try normal.fetchColor(id: original.id), originalPhysical)
            XCTAssertEqual(try fixture.referenceControl.fetchReferences(), originalReferences)
            XCTAssertEqual(try environment.fetchReferenceAnimalRevision(), originalRevision)

            try failing.upsert(blue)
            XCTAssertNil(try normal.fetchColor(id: original.id))
            XCTAssertEqual(try normal.fetchColor(id: TagColorDefaults.blueID)?.id, TagColorDefaults.blueID)
            XCTAssertEqual(try fixture.referenceControl.fetchReferences().animalTagColorID, TagColorDefaults.blueID)
            XCTAssertNotEqual(
                try environment.fetchReferenceAnimalRevision(), originalRevision,
                "Successful built-in collision repair must rotate the affected Animal's editor revision."
            )
        }
    }

    func testDuplicatePhysicalTagColorIDsRejectReadsAndWritesWithoutMutation() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let environment = CoreDataTagColorContractEnvironment(assembly: assembly)
        try environment.seedInitialHerd()

        let duplicatedID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let foreignHerdID = UUID()
        let selectedHerdID = environment.initialHerdID
        let original = TagColorSnapshot(
            id: duplicatedID,
            name: "First Physical Amber",
            prefix: "FA",
            rgba: RGBAColor(r: 0.75, g: 0.45, b: 0.2),
            sortOrder: 4
        )
        let control = TagColorSnapshot(
            name: "Unaffected Teal",
            prefix: "UT",
            rgba: RGBAColor(r: 0.1, g: 0.5, b: 0.55),
            sortOrder: 9
        )
        try environment.fixture.referenceControl.seedPersistedColor(original)
        try environment.fixture.referenceControl.seedPersistedColor(control)

        // Construct physically ambiguous UUIDs without passing through the
        // uniqueness-preserving public Tag Color repository or probe.
        let writeContext = try assembly.contextFactory.makeWriteContext()
        try writeContext.performAndWait {
            let request = NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
            request.predicate = NSPredicate(format: "id == %@", selectedHerdID as NSUUID)
            let selectedHerd = try XCTUnwrap(writeContext.fetch(request).first)

            let foreignHerd = CDHerd(context: writeContext)
            foreignHerd.id = foreignHerdID
            foreignHerd.name = "Independent Tag Color Herd"
            foreignHerd.createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
            foreignHerd.updatedAt = foreignHerd.createdAt

            func insertColor(name: String, prefix: String, herd: CDHerd) {
                let color = CDTagColorDefinition(context: writeContext)
                color.id = duplicatedID
                color.name = name
                color.prefix = prefix
                color.red = 0.2
                color.green = 0.4
                color.blue = 0.6
                color.alpha = 1
                color.sortOrder = 5
                // Hidden corruption must still fail the complete-Herd preflight.
                color.isHidden = name == "Second Physical Blue"
                color.isDefault = false
                color.createdAt = Date(timeIntervalSinceReferenceDate: 2_000)
                color.updatedAt = color.createdAt
                color.herd = herd
            }

            insertColor(name: "Second Physical Blue", prefix: "SP", herd: selectedHerd)
            insertColor(name: "Foreign Herd Blue", prefix: "FH", herd: foreignHerd)
            try writeContext.save()
        }

        func physicalState(in assembly: CoreDataPersistenceAssembly) throws -> [String] {
            let context = assembly.contextFactory.makeReadContext()
            return try context.performAndWait {
                let request = NSFetchRequest<CDTagColorDefinition>(
                    entityName: CDTagColorDefinition.coreDataEntityName
                )
                return try context.fetch(request).map { color in
                    [
                        color.herd.id.uuidString, color.id.uuidString, color.name,
                        color.prefix, String(color.sortOrder), String(color.isHidden),
                        String(color.isDefault),
                        String(color.updatedAt.timeIntervalSinceReferenceDate)
                    ].joined(separator: "|")
                }.sorted()
            }
        }

        let baseline = try physicalState(in: assembly)
        XCTAssertEqual(baseline.count, 4)
        let repository = environment.fixture.makeTagColorRepository()
        let expectedError = CoreDataPersistenceError.duplicateApplicationID(
            entity: CDTagColorDefinition.coreDataEntityName,
            id: duplicatedID,
            herdID: selectedHerdID
        )

        XCTAssertThrowsError(try repository.fetchColors()) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertThrowsError(try repository.fetchColor(id: duplicatedID)) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertThrowsError(try repository.reorder(colorIDs: [control.id])) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertThrowsError(try repository.upsert(TagColorSnapshot(
            name: "Unrelated New Color",
            prefix: "NC",
            rgba: RGBAColor(r: 0.5, g: 0.3, b: 0.1)
        ))) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertEqual(try physicalState(in: assembly), baseline)

        // The same UUID remains legitimate in another Herd, and selecting
        // that Herd must not read or repair the first Herd's invalid rows.
        environment.selection.currentHerdID = foreignHerdID
        let foreignRows = try repository.fetchColors()
        XCTAssertEqual(foreignRows.first { $0.id == duplicatedID }?.name, "Foreign Herd Blue")
        XCTAssertEqual(try repository.fetchColor(id: duplicatedID)?.name, "Foreign Herd Blue")
        XCTAssertEqual(try physicalState(in: assembly), baseline)

        let readOnlyAssembly = try await harness.makeAssembly(accessMode: .readOnly)
        let readOnlySelection = CoreDataTagColorContractSelection()
        readOnlySelection.currentHerdID = selectedHerdID
        let readOnlyRepository = CoreDataTagColorRepository(
            selection: readOnlySelection,
            assembly: readOnlyAssembly
        )
        XCTAssertThrowsError(try readOnlyRepository.fetchColors()) {
            XCTAssertEqual($0 as? CoreDataPersistenceError, expectedError)
        }
        readOnlySelection.currentHerdID = foreignHerdID
        XCTAssertEqual(
            try readOnlyRepository.fetchColor(id: duplicatedID)?.name,
            "Foreign Herd Blue"
        )
        XCTAssertEqual(try physicalState(in: readOnlyAssembly), baseline)
    }

    func testConflictingDefaultReadUsesRepairPriorityAcrossSQLiteReopen() async throws {
        let harness = try CoreDataPersistenceHarness()
        let assembly = try await harness.makeAssembly()
        let environment = CoreDataTagColorContractEnvironment(assembly: assembly)
        try environment.seedInitialHerd()

        let first = TagColorSnapshot(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            name: "Earlier Amber",
            prefix: "EA",
            rgba: RGBAColor(r: 0.85, g: 0.45, b: 0.2),
            sortOrder: 1,
            isDefault: true,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let preferred = TagColorSnapshot(
            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            name: "Newer Teal",
            prefix: "NT",
            rgba: RGBAColor(r: 0.2, g: 0.6, b: 0.65),
            sortOrder: 15,
            isDefault: true,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )
        let unaffected = TagColorSnapshot(
            id: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
            name: "Unrelated Olive",
            prefix: "UO",
            rgba: RGBAColor(r: 0.35, g: 0.55, b: 0.25),
            sortOrder: 9,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 150)
        )
        try environment.fixture.referenceControl.seedPersistedColor(first)
        try environment.fixture.referenceControl.seedPersistedColor(preferred)
        try environment.fixture.referenceControl.seedPersistedColor(unaffected)

        let repository = environment.fixture.makeTagColorRepository()
        let firstRead = try repository.fetchColors()
        let library = TagColorLibraryStore(repository: repository)
        XCTAssertEqual(library.defaultColorID, preferred.id)
        XCTAssertEqual(firstRead.filter(\.isDefault).map(\.id), [preferred.id])
        XCTAssertTrue(try XCTUnwrap(repository.fetchColor(id: first.id)).isDefault)
        XCTAssertTrue(try XCTUnwrap(repository.fetchColor(id: preferred.id)).isDefault)

        // Reading projects an exclusive default but must not heal the physical rows.
        let passiveReadOnlyAssembly = try await harness.makeAssembly(accessMode: .readOnly)
        let readSelection = CoreDataTagColorContractSelection()
        readSelection.currentHerdID = environment.initialHerdID
        let reader = CoreDataTagColorRepository(
            selection: readSelection,
            assembly: passiveReadOnlyAssembly
        )
        XCTAssertEqual(try reader.fetchColors().filter(\.isDefault).map(\.id), [preferred.id])
        XCTAssertTrue(try XCTUnwrap(reader.fetchColor(id: first.id)).isDefault)
        XCTAssertTrue(try XCTUnwrap(reader.fetchColor(id: preferred.id)).isDefault)

        // An unrelated write repairs duplicate defaults without silently
        // selecting a different color from the one shown by passive reads.
        let control = TagColorSnapshot(
            name: "Control Violet",
            prefix: "CV",
            rgba: RGBAColor(r: 0.5, g: 0.3, b: 0.7)
        )
        try repository.upsert(control)
        XCTAssertEqual(try repository.fetchColors().filter(\.isDefault).map(\.id), [preferred.id])
        XCTAssertFalse(try XCTUnwrap(repository.fetchColor(id: first.id)).isDefault)
        XCTAssertTrue(try XCTUnwrap(repository.fetchColor(id: preferred.id)).isDefault)
        XCTAssertEqual(try repository.fetchColor(id: control.id)?.id, control.id)
        XCTAssertEqual(try repository.fetchColor(id: unaffected.id), unaffected)
        library.refresh()
        XCTAssertEqual(library.defaultColorID, preferred.id)

        let freshAssembly = try await harness.makeAssembly(accessMode: .readOnly)
        let fresh = CoreDataTagColorRepository(
            selection: readSelection,
            assembly: freshAssembly
        )
        XCTAssertEqual(try fresh.fetchColors().filter(\.isDefault).map(\.id), [preferred.id])
        XCTAssertFalse(try XCTUnwrap(fresh.fetchColor(id: first.id)).isDefault)
        XCTAssertTrue(try XCTUnwrap(fresh.fetchColor(id: preferred.id)).isDefault)
    }

    func testTiedDefaultsStayConsistentThroughPartialReorderRestoreAndExplicitSelection() async throws {
        try await runRollback { environment in
            let timestamp = Date(timeIntervalSinceReferenceDate: 400)
            let amber = TagColorSnapshot(
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
                name: "Amber Control",
                prefix: "AC",
                rgba: RGBAColor(r: 0.9, g: 0.5, b: 0.1),
                sortOrder: 20,
                isDefault: true,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            let zinc = TagColorSnapshot(
                id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
                name: "Zinc Control",
                prefix: "ZC",
                rgba: RGBAColor(r: 0.4, g: 0.4, b: 0.6),
                sortOrder: 20,
                isDefault: true,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try environment.fixture.referenceControl.seedPersistedColor(amber)
            try environment.fixture.referenceControl.seedPersistedColor(zinc)
            let repo = environment.fixture.makeTagColorRepository()

            XCTAssertEqual(try repo.fetchColors().filter(\.isDefault).map(\.id), [amber.id])
            XCTAssertEqual(
                try repo.fetchColors().filter { $0.id == amber.id || $0.id == zinc.id }
                    .map(\.id),
                [amber.id, zinc.id],
                "The library must preserve stable display order when sortOrder ties."
            )

            // The losing record becomes newest when its order is changed;
            // this must not override the default seen immediately before move.
            try repo.reorder(colorIDs: [zinc.id])
            XCTAssertEqual(try repo.fetchColors().filter(\.isDefault).map(\.id), [amber.id])
            XCTAssertTrue(try XCTUnwrap(repo.fetchColor(id: amber.id)).isDefault)
            XCTAssertFalse(try XCTUnwrap(repo.fetchColor(id: zinc.id)).isDefault)
            XCTAssertEqual(try repo.fetchColor(id: zinc.id)?.sortOrder, 0)

            // Reordering a virtual built-in must not adopt its default flag or
            // change the preferred persisted color.
            try repo.reorder(colorIDs: [TagColorDefaults.blueID])
            XCTAssertEqual(try repo.fetchColors().filter(\.isDefault).map(\.id), [amber.id])

            try repo.restoreDefaultColors()
            XCTAssertEqual(try repo.fetchColors().filter(\.isDefault).map(\.id), [amber.id])
            XCTAssertTrue(try XCTUnwrap(repo.fetchColor(id: amber.id)).isDefault)
            XCTAssertFalse(try XCTUnwrap(repo.fetchColor(id: zinc.id)).isDefault)

            // An explicit new selection always wins over repair precedence.
            try repo.setDefaultColor(id: zinc.id)
            XCTAssertEqual(try repo.fetchColors().filter(\.isDefault).map(\.id), [zinc.id])
            XCTAssertTrue(try XCTUnwrap(repo.fetchColor(id: zinc.id)).isDefault)
        }
    }

    func testEditingLosingPhysicalDefaultPreservesSelectionUntilExplicitChange() async throws {
        try await runRollback { environment in
            let earlier = Date(timeIntervalSinceReferenceDate: 500)
            let later = Date(timeIntervalSinceReferenceDate: 700)
            let winning = TagColorSnapshot(
                id: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!,
                name: "Preferred Silver",
                prefix: "PS",
                rgba: RGBAColor(r: 0.75, g: 0.8, b: 0.8),
                sortOrder: 13,
                isDefault: true,
                createdAt: earlier,
                updatedAt: later
            )
            let losing = TagColorSnapshot(
                id: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!,
                name: "Earlier Bronze",
                prefix: "EB",
                rgba: RGBAColor(r: 0.65, g: 0.4, b: 0.2),
                sortOrder: 3,
                isDefault: true,
                createdAt: earlier,
                updatedAt: earlier
            )
            let control = TagColorSnapshot(
                id: UUID(uuidString: "88888888-8888-4888-8888-888888888888")!,
                name: "Untouched Coral",
                prefix: "UC",
                rgba: RGBAColor(r: 0.8, g: 0.3, b: 0.4),
                sortOrder: 8,
                createdAt: earlier,
                updatedAt: earlier
            )
            try environment.fixture.referenceControl.seedPersistedColor(winning)
            try environment.fixture.referenceControl.seedPersistedColor(losing)
            try environment.fixture.referenceControl.seedPersistedColor(control)

            let repository = environment.fixture.makeTagColorRepository()
            XCTAssertEqual(try repository.fetchColors().filter(\.isDefault).map(\.id), [winning.id])

            // A regular edit does not request default selection, even though
            // the losing physical row previously still had isDefault == true.
            let edit = TagColorSnapshot(
                id: losing.id,
                name: losing.name,
                prefix: "EB2",
                rgba: RGBAColor(r: 0.7, g: 0.45, b: 0.25),
                isDefault: false
            )
            try repository.upsert(edit)
            XCTAssertEqual(try repository.fetchColors().filter(\.isDefault).map(\.id), [winning.id])
            XCTAssertTrue(try XCTUnwrap(repository.fetchColor(id: winning.id)).isDefault)
            XCTAssertFalse(try XCTUnwrap(repository.fetchColor(id: losing.id)).isDefault)
            XCTAssertEqual(try repository.fetchColor(id: losing.id)?.prefix, "EB2")
            XCTAssertEqual(try repository.fetchColor(id: control.id), control)

            // A caller explicitly setting isDefault on an upsert remains an
            // intentional selection change, not an automatic repair side effect.
            let explicitlySelected = TagColorSnapshot(
                id: control.id,
                name: control.name,
                prefix: control.prefix,
                rgba: control.rgba,
                isDefault: true
            )
            try repository.upsert(explicitlySelected)
            XCTAssertEqual(try repository.fetchColors().filter(\.isDefault).map(\.id), [control.id])
            XCTAssertFalse(try XCTUnwrap(repository.fetchColor(id: winning.id)).isDefault)
            XCTAssertTrue(try XCTUnwrap(repository.fetchColor(id: control.id)).isDefault)
        }
    }

    func testRestoringCanonicalBuiltInsPreservesCustomConflictWinner() async throws {
        try await runRollback { environment in
            let earlier = Date(timeIntervalSinceReferenceDate: 900)
            let later = Date(timeIntervalSinceReferenceDate: 1_200)
            let winner = TagColorSnapshot(
                name: "Selected Sage",
                prefix: "SS",
                rgba: RGBAColor(r: 0.35, g: 0.7, b: 0.4),
                sortOrder: 17,
                isDefault: true,
                createdAt: earlier,
                updatedAt: later
            )
            let damagedBlue = TagColorSnapshot(
                id: TagColorDefaults.blueID,
                name: "Outdated Azure",
                prefix: "OA",
                rgba: RGBAColor(r: 0.4, g: 0.45, b: 0.6),
                sortOrder: 0,
                isDefault: true,
                createdAt: earlier,
                updatedAt: earlier
            )
            let control = TagColorSnapshot(
                name: "Unrelated Rose",
                prefix: "UR",
                rgba: RGBAColor(r: 0.75, g: 0.3, b: 0.4),
                sortOrder: 12,
                createdAt: earlier,
                updatedAt: earlier
            )
            try environment.fixture.referenceControl.seedPersistedColor(winner)
            try environment.fixture.referenceControl.seedPersistedColor(damagedBlue)
            try environment.fixture.referenceControl.seedPersistedColor(control)
            let repo = environment.fixture.makeTagColorRepository()
            XCTAssertEqual(try repo.fetchColors().filter(\.isDefault).map(\.id), [winner.id])

            try repo.restoreDefaultColors()

            XCTAssertEqual(try repo.fetchColors().filter(\.isDefault).map(\.id), [winner.id])
            XCTAssertTrue(try XCTUnwrap(repo.fetchColor(id: winner.id)).isDefault)
            let blue = try XCTUnwrap(repo.fetchColor(id: TagColorDefaults.blueID))
            XCTAssertFalse(blue.isDefault)
            XCTAssertEqual(blue.name, "Blue")
            XCTAssertEqual(blue.sortOrder, 5)
            XCTAssertEqual(try repo.fetchColor(id: control.id), control)
            XCTAssertEqual(
                try environment.fixture.makeTagColorRepository().fetchColors().filter(\.isDefault).map(\.id),
                [winner.id],
                "A fresh context must not inherit a rebuilt built-in's newer timestamp."
            )
        }
    }

    private func runRollback(
        _ assertion: (CoreDataTagColorContractEnvironment) throws -> Void
    ) async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let environment = CoreDataTagColorContractEnvironment(assembly: assembly)
        try environment.seedInitialHerd()
        try assertion(environment)
    }

    private func run(
        _ assertion: (TagColorRepositoryContractFixture) throws -> Void
    ) async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let environment = CoreDataTagColorContractEnvironment(assembly: assembly)
        try environment.seedInitialHerd()
        try assertion(environment.fixture)
    }
}

@MainActor
private final class CoreDataTagColorContractEnvironment {
    let assembly: CoreDataPersistenceAssembly
    let selection = CoreDataTagColorContractSelection()
    let initialHerdID = UUID()
    private let referenceProbe: CoreDataTagColorReferenceProbe

    init(assembly: CoreDataPersistenceAssembly) {
        self.assembly = assembly
        self.referenceProbe = CoreDataTagColorReferenceProbe(
            assembly: assembly,
            herdID: initialHerdID
        )
        selection.currentHerdID = initialHerdID
    }

    var fixture: TagColorRepositoryContractFixture {
        TagColorRepositoryContractFixture(
            makeTagColorRepository: {
                CoreDataTagColorRepository(selection: self.selection, assembly: self.assembly)
            },
            referenceControl: TagColorReferenceTestControl(
                seedPersistedColor: { snapshot in
                    try self.referenceProbe.seedPersistedColor(snapshot)
                },
                seedReferences: { id in
                    try self.referenceProbe.seedReferences(id)
                },
                fetchReferences: {
                    try self.referenceProbe.fetchReferences()
                }
            ),
            herdSelectionControl: HerdRepositorySelectionTestControl(
                seedHerd: { id, name, createdAt, updatedAt in
                    try self.seedHerd(
                        id: id, name: name, createdAt: createdAt, updatedAt: updatedAt
                    )
                },
                setCurrentHerdID: { id in
                    self.selection.currentHerdID = id
                },
                persistedHerdRowCountsByID: {
                    try self.persistedHerdRowCountsByID()
                }
            )
        )
    }

    func fetchReferenceAnimalRevision() throws -> UUID {
        try referenceProbe.fetchAnimalEditorRevision()
    }

    func makeFaultInjectingRepository(
        _ probe: CoreDataTagColorRollbackProbe
    ) -> CoreDataTagColorRepository {
        CoreDataTagColorRepository(
            selection: selection,
            assembly: assembly,
            beforeSave: { context in
                try probe.injectOnceAfterStaging(context)
            }
        )
    }

    func seedInitialHerd() throws {
        try seedHerd(
            id: initialHerdID,
            name: "Core Data Tag Color Contract Herd",
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 1_000)
        )
    }

    private func seedHerd(
        id: UUID,
        name: String,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = CDHerd(context: context)
            herd.id = id
            herd.name = name
            herd.createdAt = createdAt
            herd.updatedAt = updatedAt
            try context.save()
        }
    }

    /// Unscoped physical-row read, deliberately not filtered by selected Herd.
    private func persistedHerdRowCountsByID() throws -> [UUID: Int] {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let request = NSFetchRequest<CDHerd>(
                entityName: CDHerd.coreDataEntityName
            )
            let rows = try context.fetch(request)
            return Dictionary(
                grouping: rows, by: \.id
            ).mapValues(\.count)
        }
    }
}

@MainActor
private final class CoreDataTagColorContractSelection: CurrentHerdSelectionReading {
    var currentHerdID: UUID?
}



/// Test-only one-shot failure after a real Core Data write was staged.
/// Capturing the write context is safe: every inspection is dispatched back to
/// its private queue using performAndWait, even after the repository returned.
private final class CoreDataTagColorRollbackProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var failed = false
    private var rolledBackContext: NSManagedObjectContext?
    private let expectedRemap: (
        sourceID: UUID,
        targetID: UUID,
        originalAnimalRevision: UUID
    )?

    init(expectedRemap: (
        sourceID: UUID,
        targetID: UUID,
        originalAnimalRevision: UUID
    )? = nil) {
        self.expectedRemap = expectedRemap
    }

    func injectOnceAfterStaging(_ context: NSManagedObjectContext) throws {
        guard context.hasChanges else {
            throw CoreDataTagColorInjectedFailure.noStagedMutation
        }
        if let expectedRemap {
            let deleted = context.deletedObjects
                .compactMap { $0 as? CDTagColorDefinition }
                .contains { $0.id == expectedRemap.sourceID }
            let tags = context.updatedObjects.compactMap { $0 as? CDAnimalTag }
            let changedAnimals = context.updatedObjects.compactMap { $0 as? CDAnimal }
            let checks = context.updatedObjects.compactMap { $0 as? CDFieldCheckAnimalCheck }
            let findings = context.updatedObjects.compactMap { $0 as? CDFieldCheckFinding }
            let queues = context.updatedObjects.compactMap { $0 as? CDWorkingQueueItem }
            guard deleted,
                  tags.count >= 2,
                  tags.allSatisfy({ $0.color?.id == expectedRemap.targetID }),
                  checks.contains(where: {
                      $0.rosterTagColorIDSnapshot == expectedRemap.targetID
                          && $0.damRosterTagColorIDSnapshot == expectedRemap.targetID
                  }),
                  findings.contains(where: {
                      $0.animalDisplayTagColorIDSnapshot == expectedRemap.targetID
                  }),
                  queues.contains(where: {
                      $0.animalTagColorIDSnapshot == expectedRemap.targetID
                          && $0.animalDamDisplayTagColorIDSnapshot == expectedRemap.targetID
                  }) else {
                throw CoreDataTagColorInjectedFailure.referenceRemapNotStaged
            }
            guard changedAnimals.count == 1,
                  let changedAnimal = changedAnimals.first,
                  changedAnimal.editorRevision != expectedRemap.originalAnimalRevision,
                  tags.allSatisfy({ $0.animal === changedAnimal }) else {
                throw CoreDataTagColorInjectedFailure.animalEditorRevisionNotStaged
            }
        }
        let inject = lock.withLock { () -> Bool in
            guard !failed else { return false }
            failed = true
            rolledBackContext = context
            return true
        }
        if inject {
            throw CoreDataTagColorInjectedFailure.afterStaging
        }
    }

    func assertContextRolledBack(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let captured = lock.withLock { rolledBackContext }
        let context = try XCTUnwrap(
            captured,
            "Fault callback must capture the actual private write context.",
            file: file, line: line
        )
        try context.performAndWait {
            XCTAssertFalse(
                context.hasChanges,
                "The repository must rollback staged changes within the same context.",
                file: file, line: line
            )
            let request = NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
            XCTAssertFalse(
                try context.fetch(request).isEmpty,
                "Rollback must leave the same context usable for new fetches.",
                file: file, line: line
            )
            try context.save()
            XCTAssertFalse(context.hasChanges, file: file, line: line)
        }
    }
}

private enum CoreDataTagColorInjectedFailure: Error, Equatable {
    case noStagedMutation
    case referenceRemapNotStaged
    case animalEditorRevisionNotStaged
    case afterStaging
}
