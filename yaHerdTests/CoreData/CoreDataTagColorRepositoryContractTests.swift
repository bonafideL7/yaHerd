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

