@preconcurrency import CoreData
import Foundation
import OSLog

/// All notifications are hints. A one-element buffer coalesces bursts without
/// dropping a store: each wakeup enumerates every loaded mirrored store.
final class CoreDataHistoryWakeups: Sendable {
    let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        stream = pair.stream
        continuation = pair.continuation
    }

    func requestProcessing() { continuation.yield(()) }
    func finish() { continuation.finish() }
}

struct CoreDataHistoryStore: Hashable, Sendable {
    let identifier: String
    let url: URL

    var checkpointURL: URL {
        url.appendingPathExtension("history-checkpoint-v1")
    }
}

/// Only value metadata crosses the context queue. No object IDs, tombstone
/// contents, user records or Core Data history objects leave that queue.
struct PersistentHistoryChanges: Sendable {
    let storeID: String
    let reasons: Set<DataMutationReason>
    let requiresFullRefresh: Bool

    /// Translate Core Data entity names at the persistence boundary. Consumers
    /// see the same domain mutation reasons as locally committed changes.
    /// Classify child-only transactions too; CloudKit can import a child
    /// without a corresponding parent change in the same history page.
    init(storeID: String, entityNames: Set<String>, requiresFullRefresh: Bool) {
        self.storeID = storeID
        var reasons = Set<DataMutationReason>()
        var needsFullRefresh = requiresFullRefresh || entityNames.isEmpty
        for entity in entityNames {
            switch entity {
            case "Herd":
                reasons.insert(.herd)
                // Root changes may alter access, identity or the entire graph.
                needsFullRefresh = true
            case "TagColorDefinition":
                reasons.insert(.tagColor)
            case "AnimalStatusReference", "Animal", "AnimalTag",
                 "MovementRecord", "StatusRecord", "HealthRecord", "PregnancyCheck":
                reasons.insert(.animal)
            case "Pasture", "PastureGroup":
                reasons.insert(.pasture)
            case "FieldCheckSession", "FieldCheckAnimalCheck", "FieldCheckFinding":
                reasons.insert(.fieldCheck)
            case "WorkingSession", "WorkingQueueItem", "WorkingTreatmentRecord",
                 "WorkingTreatmentTemplate":
                reasons.insert(.working)
            default:
                // An unrecognized entity cannot safely be ignored.
                needsFullRefresh = true
            }
        }
        self.reasons = reasons
        self.requiresFullRefresh = needsFullRefresh
    }
}

enum CoreDataHistoryError: Error {
    case unidentifiedStore
    case storeChanged
    case invalidResult
    case missingTransactionFetchRequest
    case checkpointDidNotAdvance
}

/// The checkpoint is tied to the persistent store UUID as well as its file.
/// The token is a secure archive, never a timestamp or a cross-store token.
private struct HistoryCheckpoint: Codable, Equatable, Sendable {
    let storeID: String
    let token: Data?
    let transactionNumber: Int64?
}

private struct HistoryPage: Sendable {
    let checkpoint: HistoryCheckpoint?
    let changes: PersistentHistoryChanges?
    let hasMore: Bool
}

/// One consumer owns the cursor for each store, even when several scenes are
/// open. Reads are on fresh private contexts and disk I/O stays off MainActor.
actor CoreDataPersistentHistoryConsumer {
    private static let pageSize = 128
    private static let pagesPerStore = 8
    private let contextFactory: CoreDataContextFactory

    // If persistence of an already published page fails, retry that checkpoint
    // without republishing it in this process. A crash may replay it, never lose it.
    private var pendingCheckpoints: [CoreDataHistoryStore: HistoryCheckpoint] = [:]

    init(contextFactory: CoreDataContextFactory) {
        self.contextFactory = contextFactory
    }

    func run(
        wakeups: CoreDataHistoryWakeups,
        refreshInventory: @escaping @MainActor @Sendable () -> Void,
        publish: @escaping @MainActor @Sendable (PersistentHistoryChanges) -> Bool
    ) async {
        for await _ in wakeups.stream {
            guard !Task.isCancelled else { return }
            // Keep Stage 3 directory revalidation even for notifications that
            // contain no record history (for example a share metadata change).
            await refreshInventory()
            guard !contextFactory.herdImportState.blocksHerdAccess else { continue }

            // One bounded retry handles a transient fetch/checkpoint failure;
            // subsequent notifications and foreground entry can retry again.
            if !(await drain(wakeups: wakeups, publish: publish)) {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard !contextFactory.herdImportState.blocksHerdAccess else { continue }
                _ = await drain(wakeups: wakeups, publish: publish)
            }
        }
    }

    private func drain(
        wakeups: CoreDataHistoryWakeups,
        publish: @MainActor @Sendable (PersistentHistoryChanges) -> Bool
    ) async -> Bool {
        let stores: [CoreDataHistoryStore]
        do {
            stores = try contextFactory.historyStores()
        } catch {
            Self.logFailure(error, storeID: nil)
            return false
        }
        pendingCheckpoints = pendingCheckpoints.filter { stores.contains($0.key) }
        var success = true
        for store in stores {
            if Task.isCancelled || contextFactory.herdImportState.blocksHerdAccess { return true }
            do {
                let hasMore = try await consume(store, publish: publish)
                if hasMore { wakeups.requestProcessing() }
            } catch is CancellationError {
                return true
            } catch {
                success = false
                Self.logFailure(error, storeID: store.identifier)
            }
        }
        return success
    }

    private func consume(
        _ store: CoreDataHistoryStore,
        publish: @MainActor @Sendable (PersistentHistoryChanges) -> Bool
    ) async throws -> Bool {
        try contextFactory.validateHerdAccess()
        if let pending = pendingCheckpoints[store] {
            try persist(pending, for: store)
        }

        let loaded = try loadCheckpoint(for: store)
        var checkpoint = loaded.checkpoint
        var needsFullRefresh = loaded.needsFullRefresh

        for _ in 0..<Self.pagesPerStore {
            try Task.checkCancellation()
            try contextFactory.validateHerdAccess()
            let page = try await readPage(
                store: store,
                checkpoint: checkpoint,
                needsFullRefresh: needsFullRefresh
            )
            try Task.checkCancellation()
            try contextFactory.validateHerdAccess()
            guard let next = page.checkpoint else { return false }

            // A nil/invalid/expired cursor can legitimately restart at an
            // earlier transaction. Otherwise forward progress is mandatory.
            if !needsFullRefresh, page.changes?.requiresFullRefresh != true,
               let previous = checkpoint?.transactionNumber,
               let current = next.transactionNumber, current <= previous {
                throw CoreDataHistoryError.checkpointDidNotAdvance
            }
            if let changes = page.changes, !(await publish(changes)) {
                // No acknowledgement, no cursor advancement.
                throw CancellationError()
            }

            // Only a successfully processed page is eligible for a checkpoint.
            // Persist even a page of entirely local transactions.
            pendingCheckpoints[store] = next
            try persist(next, for: store)
            checkpoint = next
            needsFullRefresh = false
            if !page.hasMore { return false }
        }
        // Bound work per store so a busy private store cannot starve the shared one.
        return true
    }

    private func loadCheckpoint(
        for store: CoreDataHistoryStore
    ) throws -> (checkpoint: HistoryCheckpoint?, needsFullRefresh: Bool) {
        let data: Data
        do {
            data = try Data(contentsOf: store.checkpointURL)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain &&
                (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError) {
            // First launch or a removed checkpoint: replay available history,
            // including a broad refresh if no retained history remains.
            return (nil, true)
        }
        do {
            let checkpoint = try JSONDecoder().decode(HistoryCheckpoint.self, from: data)
            guard checkpoint.storeID == store.identifier,
                  (checkpoint.token == nil) == (checkpoint.transactionNumber == nil) else {
                return (nil, true)
            }
            return (checkpoint, false)
        } catch {
            // Corrupt bytes are not a store-load failure. Rebuild only this
            // application's cursor, without touching the SQLite history.
            Self.logFailure(error, storeID: store.identifier)
            return (nil, true)
        }
    }

    private func persist(_ checkpoint: HistoryCheckpoint, for store: CoreDataHistoryStore) throws {
        // A removed or replaced store cannot receive the previous store's token.
        guard try contextFactory.historyStores().contains(store) else {
            pendingCheckpoints.removeValue(forKey: store)
            throw CoreDataHistoryError.storeChanged
        }
        let data = try JSONEncoder().encode(checkpoint)
        try data.write(to: store.checkpointURL, options: .atomic)
        pendingCheckpoints.removeValue(forKey: store)
    }

    private func readPage(
        store: CoreDataHistoryStore,
        checkpoint: HistoryCheckpoint?,
        needsFullRefresh: Bool
    ) async throws -> HistoryPage {
        let context = contextFactory.makeReadContext()
        let localAuthor = contextFactory.localTransactionAuthor
        return try await context.perform {
            let loaded = context.persistentStoreCoordinator?.persistentStores.filter {
                $0.identifier == store.identifier && $0.url == store.url
            } ?? []
            guard loaded.count == 1, let persistentStore = loaded.first else {
                throw CoreDataHistoryError.storeChanged
            }

            var fullRefresh = needsFullRefresh
            var token: NSPersistentHistoryToken?
            if let encoded = checkpoint?.token {
                do {
                    token = try NSKeyedUnarchiver.unarchivedObject(
                        ofClass: NSPersistentHistoryToken.self, from: encoded
                    )
                    if token == nil { fullRefresh = true }
                } catch {
                    fullRefresh = true
                    Self.logFailure(error, storeID: store.identifier)
                }
            }

            let transactions: [NSPersistentHistoryTransaction]
            do {
                transactions = try Self.fetch(after: token, store: persistentStore, context: context)
            } catch let error as NSError
                where token != nil && error.domain == NSCocoaErrorDomain &&
                    error.code == NSPersistentHistoryTokenExpiredError {
                // Lost history cannot be reconstructed from a date. Publish a
                // broad refresh and establish a fresh cursor from retained history.
                fullRefresh = true
                transactions = try Self.fetch(after: nil, store: persistentStore, context: context)
            }

            guard let last = transactions.last else {
                guard fullRefresh else {
                    return HistoryPage(checkpoint: nil, changes: nil, hasMore: false)
                }
                return HistoryPage(
                    checkpoint: HistoryCheckpoint(
                        storeID: store.identifier, token: nil, transactionNumber: nil
                    ),
                    changes: PersistentHistoryChanges(
                        storeID: store.identifier, entityNames: [], requiresFullRefresh: true
                    ),
                    hasMore: false
                )
            }

            var remoteFound = false
            var entities = Set<String>()
            for transaction in transactions {
                guard transaction.storeID == store.identifier else {
                    throw CoreDataHistoryError.invalidResult
                }
                // Exact current-process authors only. Never filter by a
                // CloudKit/Apple author prefix or by the application's name.
                guard transaction.author != localAuthor else { continue }
                remoteFound = true
                guard let changes = transaction.changes, !changes.isEmpty else {
                    fullRefresh = true
                    continue
                }
                for change in changes {
                    if let name = change.changedObjectID.entity.name {
                        entities.insert(name)
                    } else {
                        fullRefresh = true
                    }
                }
            }

            let encoded = try NSKeyedArchiver.archivedData(
                withRootObject: last.token, requiringSecureCoding: true
            )
            let changes = remoteFound || fullRefresh
                ? PersistentHistoryChanges(
                    storeID: store.identifier, entityNames: entities, requiresFullRefresh: fullRefresh
                )
                : nil
            return HistoryPage(
                checkpoint: HistoryCheckpoint(
                    storeID: store.identifier, token: encoded,
                    transactionNumber: last.transactionNumber
                ),
                changes: changes,
                hasMore: transactions.count >= Self.pageSize
            )
        }
    }

    private static func fetch(
        after token: NSPersistentHistoryToken?,
        store: NSPersistentStore,
        context: NSManagedObjectContext
    ) throws -> [NSPersistentHistoryTransaction] {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        request.affectedStores = [store]
        request.resultType = .transactionsAndChanges
        guard let fetch = NSPersistentHistoryTransaction.fetchRequest else {
            throw CoreDataHistoryError.missingTransactionFetchRequest
        }
        // Preserve Core Data's native history order for token-based paging.
        // transactionNumber is a returned transaction property, not a fetchable
        // key on the SQLite history entity. Sorting by it raises NSException.
        fetch.fetchLimit = pageSize
        request.fetchRequest = fetch
        guard let result = try context.execute(request) as? NSPersistentHistoryResult else {
            throw CoreDataHistoryError.invalidResult
        }
        guard let payload = result.result else { return [] }
        guard let transactions = payload as? [NSPersistentHistoryTransaction] else {
            throw CoreDataHistoryError.invalidResult
        }
        // The history request can return more than its nested fetch limit.
        // Bound the actual acknowledged page before choosing its final token.
        // Sort the returned values, never the underlying history entity.
        return Array(transactions.sorted {
            $0.transactionNumber < $1.transactionNumber
        }.prefix(pageSize))
    }

    private static func logFailure(_ error: Error, storeID: String?) {
        let failure = error as NSError
        ReliabilityLog.persistence.error(
            "operation=history-consumption store=\(storeID ?? "unknown", privacy: .private) domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)"
        )
    }
}
