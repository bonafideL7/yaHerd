import Synchronization

/// Thread-safe handoff cache between SwiftData and the isolated Core Data bridge.
/// SwiftData revision sidecars and Core Data metadata are the durable sources;
/// this registry only carries values across actor and persistence boundaries for
/// the active operation.
enum CollaborationRevisionRegistry {
    struct Entry: Sendable {
        let key: CollaborationAggregateKey
        let metadata: CollaborationRevisionMetadata
    }

    private static let localCache = Mutex<[String: CollaborationRevisionMetadata]>([:])
    private static let observedSharedCache = Mutex<[String: CollaborationRevisionMetadata]>([:])
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
        }
    }

    /// Rehydrates the handoff cache from durable SwiftData sidecars. Persisted
    /// records intentionally replace cached values even when their revisions are
    /// lower because the active SwiftData store is authoritative.
    static func registerAuthoritativeLocals(_ entries: [Entry]) {
        guard !entries.isEmpty else { return }
        localCache.withLock { cache in
            for entry in entries {
                cache[entry.key.storageKey] = entry.metadata
            }
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
        }
    }

    static func resetForTesting() {
        localCache.withLock { $0.removeAll() }
        observedSharedCache.withLock { $0.removeAll() }
        incomingCache.withLock { $0.removeAll() }
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
}
