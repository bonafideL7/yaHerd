import Foundation

@MainActor
final class UbiquitousApplicationSettingsCloudStore: ApplicationSettingsCloudStore {
    private var store: NSUbiquitousKeyValueStore?

    /// The system store is intentionally resolved lazily. Local-only launches
    /// never use this adapter and must not require iCloud key-value entitlements.
    convenience init() {
        self.init(store: nil)
    }

    init(store: NSUbiquitousKeyValueStore) {
        self.store = store
    }

    private init(store: NSUbiquitousKeyValueStore?) {
        self.store = store
    }

    func object(forKey key: String) -> Any? {
        resolvedStore.object(forKey: key)
    }

    func set(_ value: Any, forKey key: String) {
        resolvedStore.set(value, forKey: key)
    }

    func removeObject(forKey key: String) {
        resolvedStore.removeObject(forKey: key)
    }

    func synchronize() {
        _ = resolvedStore.synchronize()
    }

    private var resolvedStore: NSUbiquitousKeyValueStore {
        if let store { return store }
        let store = NSUbiquitousKeyValueStore.default
        self.store = store
        return store
    }
}
