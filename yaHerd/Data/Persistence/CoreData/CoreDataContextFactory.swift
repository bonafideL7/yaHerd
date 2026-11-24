@preconcurrency import CoreData
import Synchronization

/// Shares only the ability to create fresh private-queue contexts with read actors.
/// The container is kept behind the same checked-Sendable Mutex pattern used by
/// Core Data's write coordinators. No managed object or context is stored here.
final class CoreDataContextFactory: Sendable {
    private let persistence: Mutex<CoreDataPersistentContainer>

    init(persistence: sending CoreDataPersistentContainer) {
        self.persistence = Mutex(persistence)
    }

    var herdImportState: HerdImportState {
        persistence.withLock { $0.herdImportState }
    }

    func makeReadContext(expectedHerdRoot: URL? = nil) -> NSManagedObjectContext {
        let context = persistence.withLock { container in
            Self.makePrivateContext(
                name: "CoreDataReadContext",
                using: container
            )
        }
        Self.bind(context, to: expectedHerdRoot)
        return context
    }

    func validateHerdAccess() throws {
        guard !herdImportState.blocksHerdAccess else {
            throw HerdRepositoryError.accountUnavailable
        }
    }

    func makeWriteContext(expectedHerdRoot: URL? = nil) throws -> NSManagedObjectContext {
        let context = try persistence.withLock { container in
            guard container.accessMode == .readWrite else {
                throw CoreDataPersistenceError.readOnlyStore
            }
            guard !container.herdImportState.blocksHerdAccess else {
                throw HerdRepositoryError.accountUnavailable
            }
            return Self.makePrivateContext(
                name: "CoreDataWriteContext",
                using: container
            )
        }
        Self.bind(context, to: expectedHerdRoot)
        return context
    }

    /// An expected root belongs to this context only. Unscoped inventory
    /// and creation contexts remain independent of the active Herd.
    private static func bind(_ context: NSManagedObjectContext, to root: URL?) {
        guard let root else { return }
        context.performAndWait {
            context.userInfo[CoreDataLookup.expectedHerdRootKey] = root
        }
    }

    private static func makePrivateContext(
        name: String,
        using container: CoreDataPersistentContainer
    ) -> NSManagedObjectContext {
        let context = container.makeBackgroundContext()
        context.name = name
        context.mergePolicy = NSErrorMergePolicy
        context.undoManager = nil
        return context
    }
}
