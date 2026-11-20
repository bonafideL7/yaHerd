import Foundation
import Observation

/// Selected Herd identity belongs to the application, not Core Data or navigation.
/// Durable storage is opt-in so recovery and isolated tests never write preferences.
@MainActor
@Observable
final class AppCurrentHerdSelection: CurrentHerdSelectionReading {
    private(set) var currentHerdID: UUID?

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let preferenceKey: String

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
        let ids = Set(accessibleHerds.map(\.id))
        if let currentHerdID, ids.contains(currentHerdID) {
            return
        }
        if let stored = defaults?.string(forKey: preferenceKey) {
            if let storedID = UUID(uuidString: stored), ids.contains(storedID) {
                currentHerdID = storedID
            } else {
                // An incomplete import or unavailable account must not cause
                // a different Herd to become selected automatically.
                currentHerdID = nil
            }
            return
        }
        currentHerdID = accessibleHerds.count == 1 ? accessibleHerds[0].id : nil
    }

    /// Reconcile only an already active Herd after a successful inventory read.
    /// Keep the saved preference when its root is temporarily absent, but never
    /// reselect it here: re-entry must pass the chooser's graph-readiness check.
    func revalidateActiveHerd(from accessibleHerds: [AccessibleHerd]) {
        guard let activeID = currentHerdID else { return }
        if accessibleHerds.filter({ $0.id == activeID }).count != 1 {
            currentHerdID = nil
        }
    }

    /// Only an accessible, unambiguous root can become the current Herd.
    func selectAccessibleHerd(_ id: UUID, from accessibleHerds: [AccessibleHerd]) throws {
        guard accessibleHerds.filter({ $0.id == id }).count == 1 else {
            throw HerdRepositoryError.missingHerd
        }
        select(id)
    }

    /// Direct selection is for already validated identities or clearing state.
    /// This preference is not a CloudKit operation or permission grant.
    func select(_ herdID: UUID?) {
        currentHerdID = herdID
        if let herdID {
            defaults?.set(herdID.uuidString, forKey: preferenceKey)
        } else {
            defaults?.removeObject(forKey: preferenceKey)
        }
    }
}
