import Foundation

@MainActor
final class UbiquitousApplicationSettingsCloudStore: ApplicationSettingsCloudStore {
    private let store: NSUbiquitousKeyValueStore

    convenience init() {
        self.init(store: .default)
    }

    init(store: NSUbiquitousKeyValueStore) {
        self.store = store
    }

    func object(forKey key: String) -> Any? {
        store.object(forKey: key)
    }

    func set(_ value: Any, forKey key: String) {
        store.set(value, forKey: key)
    }

    func removeObject(forKey key: String) {
        store.removeObject(forKey: key)
    }

    func synchronize() {
        _ = store.synchronize()
    }
}
