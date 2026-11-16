import Foundation

/// Only a confirmed, locally available Herd may become the app's selected graph.
/// A removed saved selection requires a new user choice, never an automatic switch
/// to a different account's Herd.
enum CloudKitHerdSelectionDecision: Equatable {
    case open(UUID)
    case choose
    case waitForImport(UUID)

    static func resolve(
        available: [AccessibleHerd],
        explicit: UUID?,
        remembered: UUID?
    ) -> Self {
        let ids = Set(available.map(\.id))
        if let explicit {
            return ids.contains(explicit) ? .open(explicit) : .waitForImport(explicit)
        }
        if let remembered {
            return ids.contains(remembered) ? .open(remembered) : .choose
        }
        if available.count == 1, let only = available.first {
            return .open(only.id)
        }
        return .choose
    }
}

/// Device-only selection. The Herd records themselves remain in Core Data;
/// this preference cannot create, copy, or select a Herd absent from discovery.
enum CloudKitSelectedHerdPreference {
    static let key = "yaHerd.cloudKit.selectedHerdID"

    static func load(from defaults: UserDefaults = .standard) -> UUID? {
        guard let value = defaults.string(forKey: key) else { return nil }
        return UUID(uuidString: value)
    }

    static func save(_ id: UUID, to defaults: UserDefaults = .standard) {
        defaults.set(id.uuidString, forKey: key)
    }
}
