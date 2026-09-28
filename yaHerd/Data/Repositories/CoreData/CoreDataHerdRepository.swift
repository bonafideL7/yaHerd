@preconcurrency import CoreData
import Foundation

@MainActor
final class CoreDataHerdRepository: HerdRepository {
    private let selection: any CurrentHerdSelectionReading
    private let contextFactory: CoreDataContextFactory
    private let transactionExecutor: CoreDataTransactionExecutor
    private let lookup: CoreDataLookup

    init(
        selection: any CurrentHerdSelectionReading,
        contextFactory: CoreDataContextFactory,
        transactionExecutor: CoreDataTransactionExecutor,
        lookup: CoreDataLookup
    ) {
        self.selection = selection
        self.contextFactory = contextFactory
        self.transactionExecutor = transactionExecutor
        self.lookup = lookup
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            selection: selection,
            contextFactory: assembly.contextFactory,
            transactionExecutor: assembly.transactionExecutor,
            lookup: assembly.lookup
        )
    }

    func fetchCurrentHerd() throws -> HerdSummary {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            return herd.toSummary()
        }
    }

    func renameCurrentHerd(to name: String) async throws -> HerdSummary {
        try await renameCurrentHerd(to: name, beforeSave: nil)
    }

    func renameCurrentHerd(
        to name: String,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws -> HerdSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw HerdRepositoryError.emptyName
        }
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

        let mutationDate = Date()
        let lookup = self.lookup
        return try await transactionExecutor.performWrite(beforeSave: beforeSave) { context in
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            herd.name = trimmedName
            herd.updatedAt = max(
                mutationDate,
                herd.updatedAt.addingTimeInterval(0.001)
            )

            return herd.toSummary()
        }
    }
}
