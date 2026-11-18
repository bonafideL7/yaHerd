import Foundation
import Observation

enum HerdInventoryState: Equatable {
    case loading
    case available
    case incomplete
    case unavailable
}

/// Coordinates the Herd list with the authoritative, persisted app selection.
/// No item is selected from a cached list without refreshing store access first.
@MainActor
@Observable
final class HerdDirectoryController {
    @ObservationIgnored private let repository: any HerdRepository
    @ObservationIgnored private let selection: AppCurrentHerdSelection
    @ObservationIgnored private let validateReadiness: (@MainActor (UUID) async throws -> Void)?
    @ObservationIgnored private var selectionGeneration: UInt64 = 0

    private(set) var herds: [AccessibleHerd] = []
    private(set) var inventoryState: HerdInventoryState = .loading
    private(set) var errorMessage: String?

    var selectedHerdID: UUID? { selection.currentHerdID }

    init(
        repository: any HerdRepository,
        selection: AppCurrentHerdSelection,
        validateReadiness: (@MainActor (UUID) async throws -> Void)? = nil
    ) {
        self.repository = repository
        self.selection = selection
        self.validateReadiness = validateReadiness
    }

    func refresh(reportErrors: Bool = true) {
        do {
            let accessible = try readAccessibleHerds()
            let previouslySelectedHerdID = selection.currentHerdID
            selection.revalidateActiveHerd(from: accessible)
            if selection.currentHerdID != previouslySelectedHerdID {
                selectionGeneration &+= 1
            }
            herds = accessible
            if reportErrors {
                errorMessage = nil
            }
        } catch {
            // Background import refresh must not repeatedly present error
            // dialogs; manual refresh still reports actionable failures.
            // Preserve the last good list and selection on transient errors.
            if reportErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectHerd(id: UUID) throws {
        let accessible = try readAccessibleHerds()
        try selection.selectAccessibleHerd(id, from: accessible)
        selectionGeneration &+= 1
        herds = accessible
        errorMessage = nil
    }

    /// Do not publish a partially imported Herd into the active repository graph.
    func selectHerdWhenReady(id: UUID) async throws {
        let accessible = try readAccessibleHerds()
        let matching = accessible.filter { $0.id == id }
        guard matching.count == 1, let originalHerd = matching.first else {
            throw HerdRepositoryError.missingHerd
        }
        let previousSelection = selection.currentHerdID
        let originatingSelectionRevision = selection.selectionRevision
        let originatingGeneration = selectionGeneration
        do {
            try await validateReadiness?(id)
        } catch {
            // Cancellation may race with an import-readiness failure. Report
            // cancellation rather than letting the chooser schedule a retry.
            try Task.checkCancellation()
            throw error
        }
        try Task.checkCancellation()
        guard selection.currentHerdID == previousSelection,
              selection.selectionRevision == originatingSelectionRevision,
              selectionGeneration == originatingGeneration else {
            throw CancellationError()
        }
        // An identically identified root can replace the validated root in
        // another store while CloudKit import or access changes are in flight.
        // Validate the new store's graph before activating it.
        let current = try readAccessibleHerds()
        let currentMatching = current.filter { $0.id == id }
        guard currentMatching.count == 1,
              currentMatching[0].category == originalHerd.category else {
            throw CancellationError()
        }
        try selection.selectAccessibleHerd(id, from: current)
        selectionGeneration &+= 1
        herds = current
        errorMessage = nil
    }

    @discardableResult
    func createOwnedHerd(named name: String) async throws -> HerdSummary {
        try Task.checkCancellation()
        // A failed first inventory read is not proof that the cloud or local
        // database contains no Herds. Never create a new root in that state.
        _ = try readAccessibleHerds()
        let originatingSelection = selection.currentHerdID
        let originatingSelectionRevision = selection.selectionRevision
        let originatingGeneration = selectionGeneration
        let created = try await repository.createOwnedHerd(named: name)

        // Creation may have committed before the chooser was dismissed or
        // another Herd was selected. Keep the new root without changing the
        // active Herd for an obsolete request.
        guard !Task.isCancelled,
              selection.currentHerdID == originatingSelection,
              selection.selectionRevision == originatingSelectionRevision,
              selectionGeneration == originatingGeneration else {
            refresh(reportErrors: false)
            return created
        }

        // The repository has committed the new root. Failure to reload the
        // inventory must not be reported as failed creation: retrying Create
        // would persist an unintended second Herd.
        do {
            try selectHerd(id: created.id)
        } catch {
            errorMessage = "\"\(created.name)\" was created, but could not be opened. " +
                "Refresh Herds and select it. \(error.localizedDescription)"
        }
        return created
    }

    private func readAccessibleHerds() throws -> [AccessibleHerd] {
        do {
            let inventory = try repository.fetchHerdInventory()
            inventoryState = inventory.hasIncompleteRoots ? .incomplete : .available
            return inventory.herds
        } catch {
            inventoryState = .unavailable
            throw error
        }
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func dismissError() {
        errorMessage = nil
    }
}
