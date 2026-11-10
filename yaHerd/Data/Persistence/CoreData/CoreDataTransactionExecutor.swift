@preconcurrency import CoreData
import Foundation

final class CoreDataTransactionExecutor {
    private let contextFactory: CoreDataContextFactory

    init(contextFactory: CoreDataContextFactory) {
        self.contextFactory = contextFactory
    }

    func performWrite<Result: Sendable>(
        herdID: UUID? = nil,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)? = nil,
        afterTransaction: (@Sendable () -> Void)? = nil,
        _ operation: @escaping @Sendable (NSManagedObjectContext) throws -> Result
    ) async throws -> Result {
        let context: NSManagedObjectContext
        do {
            context = try contextFactory.makeWriteContext()
        } catch {
            afterTransaction?()
            throw error
        }

        return try await context.perform {
            defer { afterTransaction?() }

            do {
                // The legacy unscoped entry point is valid only while one store
                // is loaded. In a private/shared container, an unqualified
                // insert (including legacy Herd bootstrap) has no safe owner.
                guard herdID != nil
                        || context.persistentStoreCoordinator?.persistentStores.count == 1 else {
                    throw CoreDataPersistenceError.unscopedMultiStoreWrite
                }

                let result = try operation(context)
                guard context.hasChanges else {
                    return result
                }

                try beforeSave?(context)
                if let herdID {
                    try CoreDataLookup().prepareForSave(herdID: herdID, in: context)
                }

                do {
                    try context.save()
                    return result
                } catch {
                    context.rollback()
                    throw CoreDataPersistenceError.saveFailed(
                        description: error.localizedDescription
                    )
                }
            } catch {
                if context.hasChanges {
                    context.rollback()
                }
                throw error
            }
        }
    }
}
