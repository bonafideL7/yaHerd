import Foundation
import Observation

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
            let accessible = try repository.fetchAccessibleHerds()
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
        let accessible = try repository.fetchAccessibleHerds()
        try selection.selectAccessibleHerd(id, from: accessible)
        selectionGeneration &+= 1
        herds = accessible
        errorMessage = nil
    }

    /// Do not publish a partially imported Herd into the active repository graph.
    func selectHerdWhenReady(id: UUID) async throws {
        let accessible = try repository.fetchAccessibleHerds()
        guard accessible.filter({ $0.id == id }).count == 1 else {
            throw HerdRepositoryError.missingHerd
        }
        let previousSelection = selection.currentHerdID
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
              selectionGeneration == originatingGeneration else {
            throw CancellationError()
        }
        // Recheck membership after validation; import access can change.
        let current = try repository.fetchAccessibleHerds()
        try selection.selectAccessibleHerd(id, from: current)
        selectionGeneration &+= 1
        herds = current
        errorMessage = nil
    }

    @discardableResult
    func createOwnedHerd(named name: String) async throws -> HerdSummary {
        try Task.checkCancellation()
        let originatingSelection = selection.currentHerdID
        let originatingGeneration = selectionGeneration
        let created = try await repository.createOwnedHerd(named: name)

        // Creation may have committed before the chooser was dismissed or
        // another Herd was selected. Keep the new root without changing the
        // active Herd for an obsolete request.
        guard !Task.isCancelled,
              selection.currentHerdID == originatingSelection,
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

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func dismissError() {
        errorMessage = nil
    }
}
