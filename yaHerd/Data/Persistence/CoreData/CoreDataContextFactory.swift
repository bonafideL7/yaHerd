@preconcurrency import CoreData

final class CoreDataContextFactory {
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
