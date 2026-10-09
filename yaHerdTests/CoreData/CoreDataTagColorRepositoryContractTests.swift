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
            let blue = try XCTUnwrap(baseline.first { $0.name == "Blue" })
            let probe = CoreDataTagColorRollbackProbe()
            let failing = environment.makeFaultInjectingRepository(probe)

            XCTAssertThrowsError(try failing.setDefaultColor(id: blue.id)) {
                XCTAssertEqual($0 as? CoreDataTagColorInjectedFailure, .afterStaging)
            }
            try probe.assertContextRolledBack()
            XCTAssertEqual(try normal.fetchColors(), baseline)
            try failing.setDefaultColor(id: blue.id)
            XCTAssertEqual(try normal.fetchColors().first(where: \.isDefault)?.id, blue.id)
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
