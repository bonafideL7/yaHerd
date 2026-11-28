@preconcurrency import CoreData
import Foundation
import Synchronization

final class CoreDataTransactionExecutor {
    private let contextFactory: CoreDataContextFactory

    init(contextFactory: CoreDataContextFactory) {
        self.contextFactory = contextFactory
    }

    func performWrite<Result: Sendable>(
        herdID: UUID? = nil,
        expectedHerdRoot: URL? = nil,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)? = nil,
        afterTransaction: (@Sendable () -> Void)? = nil,
        _ operation: @escaping @Sendable (NSManagedObjectContext) throws -> Result
    ) async throws -> Result {
        let contextFactory = self.contextFactory
        let context: NSManagedObjectContext
        do {
            try Task.checkCancellation()
            context = try contextFactory.makeWriteContext(expectedHerdRoot: expectedHerdRoot)
        } catch {
            afterTransaction?()
            throw error
        }

        // Core Data performs the closure on its own queue. Swift Task
        // cancellation is not visible there without an explicit bridge.
        let cancellation = Mutex(false)
        return try await withTaskCancellationHandler {
            try await context.perform {
                defer { afterTransaction?() }

                do {
                    try cancellation.withLock {
                        if $0 { throw CancellationError() }
                    }

                    // The legacy unscoped entry point is valid only while one store
                    // is loaded. In a private/shared container, an unqualified
                    // insert (including legacy Herd bootstrap) has no safe owner.
                    guard herdID != nil
                            || context.persistentStoreCoordinator?.persistentStores.count == 1 else {
                        throw CoreDataPersistenceError.unscopedMultiStoreWrite
                    }

                    let result = try operation(context)
                    try cancellation.withLock {
                        if $0 { throw CancellationError() }
                    }
                    guard context.hasChanges else {
                        return result
                    }

                    try beforeSave?(context)
                    try contextFactory.authorizeSave(in: context, herdID: herdID)
                    // A Herd switch may cancel the caller while changes are
                    // staged. Roll them back unless the save has already begun.
                    try cancellation.withLock {
                        if $0 { throw CancellationError() }
                    }
                    do {
                        try context.save()
                        return result
                    } catch {
                        ReliabilityLog.persistenceSaveFailure("transaction-save", error: error)
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
        } onCancel: {
            cancellation.withLock { $0 = true }
        }
    }
}
