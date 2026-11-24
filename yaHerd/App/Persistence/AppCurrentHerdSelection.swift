import Foundation
import Observation

/// Owns the selected Herd and its local store-qualified root identity.
/// Preferences restore access only after a successful inventory read.
@MainActor
@Observable
final class AppCurrentHerdSelection: CurrentHerdSelectionReading {
    private(set) var currentHerdID: UUID?
    private(set) var selectionRevision: UInt64 = 0

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let preferenceKey: String
    @ObservationIgnored private var activeHerd: AccessibleHerd?

    private var storeCategoryPreferenceKey: String { preferenceKey + ".storeCategory" }
    private var rootIdentityPreferenceKey: String { preferenceKey + ".rootIdentity" }

    var selectedRootIdentity: URL? { activeHerd?.rootIdentity }
    var hasRememberedHerd: Bool {
        rememberedHerdID != nil
    }

    private var rememberedHerdID: UUID? {
        UUID(uuidString: defaults?.string(forKey: preferenceKey) ?? "")
    }

    init(
        currentHerdID: UUID? = nil,
        defaults: UserDefaults? = nil,
        preferenceKey: String = "yaHerd.selectedHerdID.v1"
    ) {
        self.currentHerdID = currentHerdID
        self.defaults = defaults
        self.preferenceKey = preferenceKey
    }

    func rememberedAccessibleHerd(from accessibleHerds: [AccessibleHerd]) -> AccessibleHerd? {
        guard let rememberedHerdID else { return nil }
        let matches = accessibleHerds.filter { $0.id == rememberedHerdID }
        guard matches.count == 1, let herd = matches.first else { return nil }
        let category = herd.category == .owned ? "owned" : "shared"
        // UUID-only local preferences identify an owned Herd, never a shared one.
        guard (defaults?.string(forKey: storeCategoryPreferenceKey) ?? "owned") == category else {
            return nil
        }
        if let identity = defaults?.string(forKey: rootIdentityPreferenceKey),
           identity != herd.rootIdentity.absoluteString {
            return nil
        }
        return herd
    }

    func restoreAccessibleHerd(from accessibleHerds: [AccessibleHerd], allowAutomaticChoice: Bool = true) {
        if let herd = rememberedAccessibleHerd(from: accessibleHerds) {
            activate(herd, remember: true)
        } else if !hasRememberedHerd, allowAutomaticChoice, accessibleHerds.count == 1,
                  let herd = accessibleHerds.first {
            activate(herd, remember: true)
        }
    }

    /// A successfully read inventory is authoritative for the active root.
    /// Absence, ambiguity or replacement invalidates all existing UI work,
    /// while the preference remains available for a later explicit reopening.
    func revalidateActiveHerd(from accessibleHerds: [AccessibleHerd]) {
        guard let currentHerdID else { return }
        let matches = accessibleHerds.filter { $0.id == currentHerdID }
        guard matches.count == 1, let herd = matches.first,
              activeHerd == nil || (
                  activeHerd?.category == herd.category &&
                  activeHerd?.rootIdentity == herd.rootIdentity
              ) else {
            deferCurrentHerdUntilImportReady()
            return
        }
        // Metadata such as a renamed Herd does not change its selection revision.
        activeHerd = herd
    }

    func deferCurrentHerdUntilImportReady() {
        guard currentHerdID != nil else { return }
        activeHerd = nil
        currentHerdID = nil
        selectionRevision &+= 1
    }

    func selectAccessibleHerd(
        _ id: UUID,
        from accessibleHerds: [AccessibleHerd],
        remember: Bool = true
    ) throws {
        let matches = accessibleHerds.filter { $0.id == id }
        guard matches.count == 1, let herd = matches.first else {
            throw HerdRepositoryError.missingHerd
        }
        activate(herd, remember: remember)
    }

    private func activate(_ herd: AccessibleHerd, remember shouldRemember: Bool) {
        let changed = currentHerdID != herd.id
            || activeHerd?.category != herd.category
            || activeHerd?.rootIdentity != herd.rootIdentity
        activeHerd = herd
        currentHerdID = herd.id
        if changed { selectionRevision &+= 1 }
        if shouldRemember { remember(herd) }
    }

    private func remember(_ herd: AccessibleHerd) {
        defaults?.set(herd.id.uuidString, forKey: preferenceKey)
        defaults?.set(herd.category == .owned ? "owned" : "shared", forKey: storeCategoryPreferenceKey)
        defaults?.set(herd.rootIdentity.absoluteString, forKey: rootIdentityPreferenceKey)
    }
}
