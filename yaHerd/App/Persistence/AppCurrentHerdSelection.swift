import Foundation
import Observation

/// Selected Herd identity belongs to the application, not Core Data or navigation.
/// Durable storage is opt-in so recovery and isolated tests never write preferences.
@MainActor
@Observable
final class AppCurrentHerdSelection: CurrentHerdSelectionReading {
    private(set) var currentHerdID: UUID?
    private(set) var selectionRevision: UInt64 = 0

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let preferenceKey: String

    private var storeCategoryPreferenceKey: String { preferenceKey + ".storeCategory" }

    init(
        currentHerdID: UUID? = nil,
        defaults: UserDefaults? = nil,
        preferenceKey: String = "yaHerd.selectedHerdID.v1"
    ) {
        self.currentHerdID = currentHerdID
        self.defaults = defaults
        self.preferenceKey = preferenceKey
    }

    /// Invoke only after a successful inventory fetch. Do not destroy the
    /// saved identity when CloudKit has not yet imported any roots.
    /// A multi-Herd inventory without a valid preference needs an explicit choice.
    func restoreAccessibleHerd(from accessibleHerds: [AccessibleHerd]) {
        if let currentHerdID {
            let matches = accessibleHerds.filter { $0.id == currentHerdID }
            if matches.count == 1,
               (defaults?.string(forKey: preferenceKey) != currentHerdID.uuidString
                || matchesRememberedStoreCategory(matches[0].category)) {
                // An explicit in-memory choice takes precedence over another
                // remembered UUID. For the same UUID, its store must still match.
                return
            }
        }
        if let stored = defaults?.string(forKey: preferenceKey) {
            let storedHerds = UUID(uuidString: stored).map { storedID in
                accessibleHerds.filter { $0.id == storedID }
            } ?? []
            if storedHerds.count == 1,
               matchesRememberedStoreCategory(storedHerds[0].category) {
                setCurrentHerdID(storedHerds[0].id)
                rememberStoreCategory(storedHerds[0].category)
            } else {
                // An incomplete import, unavailable account, or root that
                // moved to another store must require explicit selection.
                setCurrentHerdID(nil)
            }
            return
        }
        if accessibleHerds.count == 1 {
            select(accessibleHerds[0].id)
            rememberStoreCategory(accessibleHerds[0].category)
        } else {
            setCurrentHerdID(nil)
        }
    }

    /// Reconcile only an already active Herd after a successful inventory read.
    /// Keep the saved preference when its root is temporarily absent, but never
    /// reselect it here: re-entry must pass the chooser's graph-readiness check.
    func revalidateActiveHerd(from accessibleHerds: [AccessibleHerd]) {
        guard let activeID = currentHerdID else { return }
        let matching = accessibleHerds.filter { $0.id == activeID }
        guard matching.count == 1,
              matchesRememberedStoreCategory(matching[0].category) else {
            setCurrentHerdID(nil)
            return
        }
        rememberStoreCategory(matching[0].category)
    }

    /// A remembered Herd may have an imported root before its related records
    /// are ready. Show the chooser without erasing the user's saved preference.
    /// The next activation must pass Herd-directory readiness validation.
    func deferCurrentHerdUntilImportReady() {
        setCurrentHerdID(nil)
    }

    /// Only an accessible, unambiguous root can become the current Herd.
    func selectAccessibleHerd(_ id: UUID, from accessibleHerds: [AccessibleHerd]) throws {
        let matching = accessibleHerds.filter { $0.id == id }
        guard matching.count == 1, let herd = matching.first else {
            throw HerdRepositoryError.missingHerd
        }
        if currentHerdID == id && !matchesRememberedStoreCategory(herd.category) {
            // Equal UUIDs are not the same active selection when ownership
            // changes. Force a new selection revision for navigation reset.
            setCurrentHerdID(nil)
        }
        select(id)
        rememberStoreCategory(herd.category)
    }

    /// A revision distinguishes a new selection from a previously opened editor,
    /// even when the user switches away and back to the same Herd UUID.
    private func setCurrentHerdID(_ herdID: UUID?) {
        guard currentHerdID != herdID else { return }
        currentHerdID = herdID
        selectionRevision &+= 1
    }

    /// Direct selection is for already validated identities or clearing state.
    /// This preference is not a CloudKit operation or permission grant.
    func select(_ herdID: UUID?) {
        if currentHerdID != herdID {
            // Direct selection does not establish a store identity; only
            // selectAccessibleHerd or a successful inventory read can do so.
            defaults?.removeObject(forKey: storeCategoryPreferenceKey)
        }
        setCurrentHerdID(herdID)
        if let herdID {
            defaults?.set(herdID.uuidString, forKey: preferenceKey)
        } else {
            defaults?.removeObject(forKey: preferenceKey)
            defaults?.removeObject(forKey: storeCategoryPreferenceKey)
        }
    }

    private func matchesRememberedStoreCategory(_ category: AccessibleHerd.Category) -> Bool {
        guard let remembered = defaults?.string(forKey: storeCategoryPreferenceKey) else {
            // An existing preference without a category is adopted on the
            // first successful inventory lookup.
            return true
        }
        return remembered == (category == .owned ? "owned" : "shared")
    }

    private func rememberStoreCategory(_ category: AccessibleHerd.Category) {
        defaults?.set(category == .owned ? "owned" : "shared", forKey: storeCategoryPreferenceKey)
    }
}
