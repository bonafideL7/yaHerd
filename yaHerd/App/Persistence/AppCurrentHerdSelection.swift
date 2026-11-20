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
        if let stored = defaults?.string(forKey: preferenceKey),
           let storedID = UUID(uuidString: stored),
           ids.contains(storedID) {
            currentHerdID = storedID
            return
        }
        currentHerdID = accessibleHerds.count == 1 ? accessibleHerds[0].id : nil
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

/// The UI never changes the selected Herd without checking current store access.
/// In particular, stale list entries and partially imported roots are not selectable.
@MainActor
@Observable
final class HerdDirectoryController {
    @ObservationIgnored private let repository: any HerdRepository
    @ObservationIgnored private let selection: AppCurrentHerdSelection

    private(set) var herds: [AccessibleHerd] = []
    private(set) var errorMessage: String?

    var selectedHerdID: UUID? { selection.currentHerdID }

    init(repository: any HerdRepository, selection: AppCurrentHerdSelection) {
        self.repository = repository
        self.selection = selection
    }

    func refresh() {
        do {
            herds = try repository.fetchAccessibleHerds()
            errorMessage = nil
        } catch {
            // Retain the last known inventory when a read temporarily fails.
            // A subsequent selection always rechecks the repository.
            errorMessage = error.localizedDescription
        }
    }

    func selectHerd(id: UUID) throws {
        let accessible = try repository.fetchAccessibleHerds()
        guard accessible.contains(where: { $0.id == id }) else {
            throw HerdRepositoryError.missingHerd
        }
        herds = accessible
        selection.select(id)
        errorMessage = nil
    }

    @discardableResult
    func createOwnedHerd(named name: String) async throws -> HerdSummary {
        let created = try await repository.createOwnedHerd(named: name)
        try selectHerd(id: created.id)
        return created
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func dismissError() {
        errorMessage = nil
    }
}
