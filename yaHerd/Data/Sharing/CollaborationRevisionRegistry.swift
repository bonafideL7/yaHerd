import Foundation
import Synchronization

/// Thread-safe metadata cache used at the boundary between SwiftData snapshots
/// and the isolated Core Data bridge. SwiftData remains the durable source; the
/// cache avoids passing persistence contexts into background bridge transactions.
enum CollaborationRevisionRegistry {
    struct Entry: Sendable {
        let key: CollaborationAggregateKey
        let metadata: CollaborationRevisionMetadata
    }

    private static let localDefaultsKey = "CollaborationRevisionRegistry.local.v1"
    private static let observedSharedDefaultsKey = "CollaborationRevisionRegistry.shared.v1"

    private static let localCache = Mutex<[String: CollaborationRevisionMetadata]>(
        loadPersistedCache(key: localDefaultsKey)
    )
    private static let observedSharedCache = Mutex<[String: CollaborationRevisionMetadata]>(
        loadPersistedCache(key: observedSharedDefaultsKey)
    )
    private static let incomingCache = Mutex<[String: CollaborationRevisionMetadata]>([:])

    static func localMetadata(for key: CollaborationAggregateKey) -> CollaborationRevisionMetadata? {
        localCache.withLock { $0[key.storageKey] }
    }

    static func observedSharedMetadata(for key: CollaborationAggregateKey) -> CollaborationRevisionMetadata? {
        observedSharedCache.withLock { $0[key.storageKey] }
    }

    static func incomingMetadata(for key: CollaborationAggregateKey) -> CollaborationRevisionMetadata? {
        incomingCache.withLock { $0[key.storageKey] }
    }

    static func registerLocal(_ metadata: CollaborationRevisionMetadata, for key: CollaborationAggregateKey) {
        localCache.withLock { cache in
            cache[key.storageKey] = preferred(existing: cache[key.storageKey], incoming: metadata)
            persist(cache, key: localDefaultsKey)
        }
    }

    /// Rehydrates the bridge handoff cache from durable SwiftData sidecars in a
    /// single write. Persisted records intentionally replace cached values even
    /// when their revisions are lower because the active store is authoritative.
    static func registerAuthoritativeLocals(_ entries: [Entry]) {
        guard !entries.isEmpty else { return }
        localCache.withLock { cache in
            for entry in entries {
                cache[entry.key.storageKey] = entry.metadata
            }
            persist(cache, key: localDefaultsKey)
        }
    }

    static func registerAuthoritativeLocal(
        _ metadata: CollaborationRevisionMetadata,
        for key: CollaborationAggregateKey
    ) {
        registerAuthoritativeLocals([Entry(key: key, metadata: metadata)])
    }

    /// Incoming metadata represents the exact bridge snapshot currently being
    /// compared or imported. It must replace an earlier export/read value even
    /// when the incoming revision is lower, otherwise stale local metadata can
    /// be misidentified as the shared side of a conflict.
    static func registerIncoming(_ metadata: CollaborationRevisionMetadata, for key: CollaborationAggregateKey) {
        incomingCache.withLock { cache in
            cache[key.storageKey] = metadata
        }
    }

    static func registerObservedShared(
        _ metadata: CollaborationRevisionMetadata,
        for key: CollaborationAggregateKey
    ) {
        registerIncoming(metadata, for: key)
        observedSharedCache.withLock { cache in
            cache[key.storageKey] = preferred(existing: cache[key.storageKey], incoming: metadata)
            persist(cache, key: observedSharedDefaultsKey)
        }
    }

    static func resetForTesting() {
        localCache.withLock { $0.removeAll() }
        observedSharedCache.withLock { $0.removeAll() }
        incomingCache.withLock { $0.removeAll() }
        UserDefaults.standard.removeObject(forKey: localDefaultsKey)
        UserDefaults.standard.removeObject(forKey: observedSharedDefaultsKey)
    }

    private static func preferred(
        existing: CollaborationRevisionMetadata?,
        incoming: CollaborationRevisionMetadata
    ) -> CollaborationRevisionMetadata {
        guard let existing else { return incoming }
        if incoming.revision != existing.revision {
            return incoming.revision > existing.revision ? incoming : existing
        }
        return incoming.modifiedAt >= existing.modifiedAt ? incoming : existing
    }

    private static func loadPersistedCache(
        key: String
    ) -> [String: CollaborationRevisionMetadata] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode(
            [String: CollaborationRevisionMetadata].self,
            from: data
        )) ?? [:]
    }

    private static func persist(
        _ cache: [String: CollaborationRevisionMetadata],
        key: String
    ) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
