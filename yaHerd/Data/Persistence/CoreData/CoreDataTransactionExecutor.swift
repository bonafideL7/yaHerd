@preconcurrency import CoreData

final class CoreDataTransactionExecutor {
    private let contextFactory: CoreDataContextFactory

    init(contextFactory: CoreDataContextFactory) {
        self.contextFactory = contextFactory
    }

    func performWrite<Result: Sendable>(
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
                let result = try operation(context)
                guard context.hasChanges else {
                    return result
                }

                try beforeSave?(context)

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
