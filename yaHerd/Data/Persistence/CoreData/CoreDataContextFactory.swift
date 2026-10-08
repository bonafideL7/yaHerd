@preconcurrency import CoreData

/// Sendable boundary for constructing independent private-queue Core Data contexts.
/// Only the immutable container reference crosses actor boundaries; each call
/// creates a fresh context and no managed object/context is shared between actors.
/// NSPersistentContainer supports creation of background contexts across queues.
final class CoreDataContextFactory: @unchecked Sendable {
    private let persistence: CoreDataPersistentContainer

    init(persistence: CoreDataPersistentContainer) {
        self.persistence = persistence
    }

    func makeReadContext() -> NSManagedObjectContext {
        makePrivateContext(name: "CoreDataReadContext")
    }

    func makeWriteContext() throws -> NSManagedObjectContext {
        guard persistence.accessMode == .readWrite else {
            throw CoreDataPersistenceError.readOnlyStore
        }
        return makePrivateContext(name: "CoreDataWriteContext")
    }

    private func makePrivateContext(name: String) -> NSManagedObjectContext {
        let context = persistence.makeBackgroundContext()
        context.name = name
        context.mergePolicy = NSErrorMergePolicy
        context.undoManager = nil
        return context
    }
}
