@preconcurrency import CoreData

final class CoreDataTransactionExecutor {
    private let contextFactory: CoreDataContextFactory

    init(contextFactory: CoreDataContextFactory) {
        self.contextFactory = contextFactory
    }

    func performWrite<Result: Sendable>(
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)? = nil,
        _ operation: @escaping @Sendable (NSManagedObjectContext) throws -> Result
    ) async throws -> Result {
        let context = try contextFactory.makeWriteContext()

        return try await context.perform {
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
