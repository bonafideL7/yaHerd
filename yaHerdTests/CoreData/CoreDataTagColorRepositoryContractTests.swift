@preconcurrency import CoreData
import Foundation
import XCTest
@testable import yaHerd

/// M11 replacement for the first nine persistence-neutral Tag Color contract
/// assertions. The reference-remap/history assertions require a separate real
/// CDAnimalTag/Field Check/Working fixture and are deliberately not claimed here.
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

    init(assembly: CoreDataPersistenceAssembly) {
        self.assembly = assembly
        selection.currentHerdID = initialHerdID
    }

    var fixture: TagColorRepositoryContractFixture {
        TagColorRepositoryContractFixture(
            makeTagColorRepository: {
                CoreDataTagColorRepository(selection: self.selection, assembly: self.assembly)
            },
            referenceControl: TagColorReferenceTestControl(
                seedPersistedColor: { _ in
                    throw CoreDataTagColorContractHarnessError.referenceGraphNotConfigured
                },
                seedReferences: { _ in
                    throw CoreDataTagColorContractHarnessError.referenceGraphNotConfigured
                },
                fetchReferences: {
                    throw CoreDataTagColorContractHarnessError.referenceGraphNotConfigured
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

private enum CoreDataTagColorContractHarnessError: Error {
    /// The three reference-remapping contracts must not silently use stub
    /// rows. A subsequent M11 PR will install real Core Data record fixtures.
    case referenceGraphNotConfigured
}
