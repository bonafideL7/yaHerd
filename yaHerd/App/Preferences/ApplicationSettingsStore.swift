import Foundation

@MainActor
protocol ApplicationSettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any, forKey key: String)
    func removeObject(forKey key: String)
}

@MainActor
final class UserDefaultsApplicationSettingsStore: ApplicationSettingsStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func object(forKey key: String) -> Any? {
        userDefaults.object(forKey: key)
    }

    func set(_ value: Any, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
}

@MainActor
enum ApplicationSettingsKeyMigrator {
    static func migrate(store: any ApplicationSettingsStore) {
        migrate(
            keys: ApplicationSettingKey.allCases,
            read: { store.object(forKey: $0) },
            write: { store.set($1, forKey: $0) },
            remove: { store.removeObject(forKey: $0) }
        )
    }

    static func migrate(
        keys: [ApplicationSettingKey],
        read: (String) -> Any?,
        write: (String, Any) -> Void,
        remove: (String) -> Void
    ) {
        for key in keys {
            if read(key.rawValue) == nil {
                for legacyKey in key.legacyKeys {
                    guard let value = read(legacyKey) else { continue }
                    write(key.rawValue, value)
                    break
                }
            }

            for legacyKey in key.legacyKeys {
                remove(legacyKey)
            }
        }

        write(
            ApplicationSettingsCatalog.schemaVersionKey,
            ApplicationSettingsCatalog.currentSchemaVersion
        )
    }
}
