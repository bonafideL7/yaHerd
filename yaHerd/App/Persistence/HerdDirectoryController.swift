import Foundation
import Observation

enum HerdDirectoryError: LocalizedError, Equatable {
    case creationInProgress
    case pendingHerdUnavailable

    var errorDescription: String? {
        switch self {
        case .creationInProgress:
            return "A Herd is already being created. Finish that request before creating another."
        case .pendingHerdUnavailable:
            return "This Herd is no longer available. Refresh the list to check for it or choose another Herd."
        }
    }
}

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
    @ObservationIgnored private var isCreatingHerd = false

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
            if let previouslySelectedHerdID,
               let previous = herds.first(where: { $0.id == previouslySelectedHerdID }),
               let refreshed = accessible.first(where: { $0.id == previouslySelectedHerdID }),
               (previous.category != refreshed.category ||
                previous.summary.createdAt != refreshed.summary.createdAt) {
                // The same UUID now identifies a different store or Herd root.
                // Do not carry the old selection into that replacement Herd.
                // A user may reopen it through the graph-readiness preflight.
                selection.deferCurrentHerdUntilImportReady()
            } else {
                selection.revalidateActiveHerd(from: accessible)
            }
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

    /// A missing root after a successful inventory refresh is no longer an
    /// import-readiness retry candidate. Inventory failures are inconclusive:
    /// keep waiting rather than treating a temporary store error as revocation.
    func shouldContinueWaitingForHerd(id: UUID) -> Bool {
        refresh(reportErrors: false)
        switch inventoryState {
        case .loading, .unavailable, .incomplete:
            // An incomplete root may already have this UUID but cannot yet
            // appear in the selectable list. Absence is not proof of removal.
            return true
        case .available:
            return herds.contains { $0.id == id }
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
    func selectHerdWhenReady(id: UUID, expectedRoot: AccessibleHerd? = nil) async throws {
        let accessible = try readAccessibleHerds()
        let matching = accessible.filter { $0.id == id }
        guard matching.count == 1, let originalHerd = matching.first else {
            throw HerdRepositoryError.missingHerd
        }
        // A pending import retry must continue opening the root the user tapped,
        // not a replacement from another store (or another root in that store)
        // that happens to reuse its UUID.
        if let expectedRoot,
           (expectedRoot.id != originalHerd.id ||
            expectedRoot.category != originalHerd.category ||
            expectedRoot.summary.createdAt != originalHerd.summary.createdAt) {
            throw HerdDirectoryError.pendingHerdUnavailable
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
        // A replaced root is not authorized by the previous root's readiness
        // result, even when it reuses the same UUID and store category. A
        // normal rename does not change the original creation timestamp.
        let current = try readAccessibleHerds()
        let currentMatching = current.filter { $0.id == id }
        guard currentMatching.count == 1,
              currentMatching[0].category == originalHerd.category,
              currentMatching[0].summary.createdAt == originalHerd.summary.createdAt else {
            throw CancellationError()
        }
        try selection.selectAccessibleHerd(id, from: current)
        selectionGeneration &+= 1
        herds = current
        errorMessage = nil
    }

    @discardableResult
    func createOwnedHerd(named name: String) async throws -> HerdSummary {
        guard !isCreatingHerd else { throw HerdDirectoryError.creationInProgress }
        isCreatingHerd = true
        defer { isCreatingHerd = false }

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
            // Every inventory caller must fail closed when the currently
            // selected root no longer identifies exactly one owning store.
            // Preserve its remembered UUID for an explicit later reopening.
            if let activeID = selection.currentHerdID,
               let persistenceError = error as? CoreDataPersistenceError {
                switch persistenceError {
                case .duplicateApplicationID(let entity, let id, _)
                    where entity == CDHerd.coreDataEntityName && id == activeID:
                    selection.deferCurrentHerdUntilImportReady()
                    selectionGeneration &+= 1
                    herds = []
                case .unresolvedHerdStore(let id) where id == activeID:
                    selection.deferCurrentHerdUntilImportReady()
                    selectionGeneration &+= 1
                    herds = []
                default:
                    break
                }
            }
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
