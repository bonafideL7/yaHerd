@preconcurrency import CoreData
import Synchronization
import Foundation
import UIKit

/// Shares only the ability to create fresh private-queue contexts with read actors.
/// The container is kept behind the same checked-Sendable Mutex pattern used by
/// Core Data's write coordinators. No managed object or context is stored here.
final class CoreDataContextFactory: Sendable {
    private let persistence: Mutex<CoreDataPersistentContainer>
    private let sharePreparationInProgress = Mutex(false)
    private let lastLocalSave = Mutex<Date?>(nil)
    private let localSaveObserver = Mutex<(any NSObjectProtocol)?>(nil)
    // Only this running process can claim its own published local saves.
    // Older or unknown authors are processed conservatively.
    let localTransactionAuthor = "yaHerd.local." + UUID().uuidString

    var historyWakeups: CoreDataHistoryWakeups? {
        persistence.withLock { $0.historyWakeups }
    }

    func historyStores() throws -> [CoreDataHistoryStore] {
        try persistence.withLock { container in
            // Store identity enumeration is independent of notification registration.
            // Runtime consumption is started only when CloudKit wakeups are installed.
            return try container.persistentStoreCoordinator.persistentStores.map { store in
                let identifier: String? = store.identifier
                guard store.type == NSSQLiteStoreType,
                      let identifier, !identifier.isEmpty,
                      let url = store.url, url.isFileURL else {
                    throw CoreDataHistoryError.unidentifiedStore
                }
                return CoreDataHistoryStore(identifier: identifier, url: url)
            }
        }
    }

    func sharingMetadata(for objectIDs: [NSManagedObjectID]) -> [NSManagedObjectID: HerdSharingMetadata] {
        persistence.withLock { $0.sharingMetadata(for: objectIDs) }
    }

    func discoverOwnedShare(for selection: HerdSelectionSnapshot) async throws -> HerdShareDiscovery {
        try validateHerdAccess()
        guard let id = selection.id, let identity = selection.rootIdentity else {
            throw HerdRepositoryError.missingHerd
        }
        let context = makeReadContext(expectedHerdRoot: identity)
        let graph = try await context.perform {
            let lookup = CoreDataLookup()
            guard let root = try lookup.herd(id: id, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            _ = try root.toSummary()
            let objects = try lookup.objectsForSharing(root: root, in: context)
            return (root.objectID, objects.map(\.objectID))
        }
        let result = try persistence.withLock {
            try $0.inspectOwnedShare(rootID: graph.0, objectIDs: graph.1)
        }
        try validateHerdAccess()
        return result
    }

    func prepareOwnedShare(for selection: HerdSelectionSnapshot) async throws -> HerdShareDiscovery {
        try Task.checkCancellation()
        try validateHerdAccess()
        guard let id = selection.id, let identity = selection.rootIdentity else {
            throw HerdRepositoryError.missingHerd
        }
        // Shared by all callers of this factory, including other scenes.
        // Do not release the reservation merely because a UI task cancels;
        // the native sharing operation may still be committing a share.
        let reserved = sharePreparationInProgress.withLock { active in
            guard !active else { return false }
            active = true
            return true
        }
        guard reserved else { throw CoreDataHerdSharingError.inProgress }
        defer { sharePreparationInProgress.withLock { $0 = false } }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try persistence.withLock {
                    try $0.prepareOwnedShare(herdID: id, rootIdentity: identity) { result in
                        continuation.resume(with: result)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        // Native completion is not proof that every current child belongs to
        // the same zone; re-read a fresh graph and the persisted share cache.
        try validateHerdAccess()
        let discovered = try await discoverOwnedShare(for: selection)
        guard case .existing = discovered else {
            throw CoreDataHerdSharingError.incompleteMembership
        }
        historyWakeups?.requestProcessing()
        return discovered
    }

    @MainActor
    func makeOwnedSharingController(
        rootIdentity: URL,
        onChange: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable () -> Void
    ) throws -> UIViewController {
        let presentation = try persistence.withLock {
            try $0.makeOwnedSharingPresentation(
                rootIdentity: rootIdentity, onChange: onChange, onFailure: onFailure
            )
        }
        return presentation()
    }

    var cloudStoreActivity: [String: CloudStoreActivity] {
        persistence.withLock { $0.cloudStoreActivity }
    }

    var storageActivity: StorageActivitySnapshot {
        StorageActivitySnapshot(
            lastLocalSave: lastLocalSave.withLock { $0 },
            cloud: persistence.withLock { $0.cloudStorageActivity }
        )
    }

    init(persistence: sending CoreDataPersistentContainer) {
        self.persistence = Mutex(persistence)

        // One observer covers the transaction executor and direct repository
        // saves. The author identifies only this factory's local write contexts.
        // Notifications arrive on the saving context's queue.
        let observer = NotificationCenter.default.addObserver(
            forName: NSManagedObjectContext.didSaveObjectIDsNotification,
            object: nil, queue: nil
        ) { [weak self] notification in
            guard let self, let context = notification.object as? NSManagedObjectContext,
                  context.transactionAuthor == self.localTransactionAuthor,
                  context.parent == nil else { return }

            let changed = [NSInsertedObjectIDsKey, NSUpdatedObjectIDsKey, NSDeletedObjectIDsKey]
                .contains { key in
                    guard let ids = notification.userInfo?[key] as? Set<NSManagedObjectID> else {
                        return false
                    }
                    return ids.contains { $0.persistentStore?.type == NSSQLiteStoreType }
                }
            guard changed else { return }

            self.lastLocalSave.withLock { $0 = Date() }
            NotificationCenter.default.post(name: CoreDataPersistentContainer.storageActivityChanged, object: nil)
        }
        localSaveObserver.withLock { $0 = observer }
    }

    deinit {
        localSaveObserver.withLock { observer in
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
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
        let author = localTransactionAuthor
        context.performAndWait {
            context.transactionAuthor = author
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
