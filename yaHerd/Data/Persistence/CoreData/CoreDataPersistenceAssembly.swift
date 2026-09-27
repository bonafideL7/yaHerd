import Foundation

final class CoreDataPersistenceAssembly {
    let persistence: CoreDataPersistentContainer
    let contextFactory: CoreDataContextFactory
    let transactionExecutor: CoreDataTransactionExecutor
    let lookup: CoreDataLookup

    init(persistence: CoreDataPersistentContainer) {
        self.persistence = persistence
        self.contextFactory = CoreDataContextFactory(persistence: persistence)
        self.transactionExecutor = CoreDataTransactionExecutor(
            contextFactory: contextFactory
        )
        self.lookup = CoreDataLookup()
    }

    static func load(
        storeURL: URL,
        accessMode: CoreDataStoreAccessMode = .readWrite
    ) async throws -> CoreDataPersistenceAssembly {
        CoreDataPersistenceAssembly(
            persistence: try await CoreDataPersistentContainer.load(
                storeURL: storeURL,
                accessMode: accessMode
            )
        )
    }

    static func inMemory() async throws -> CoreDataPersistenceAssembly {
        CoreDataPersistenceAssembly(
            persistence: try await CoreDataPersistentContainer.inMemory()
        )
    }
}
