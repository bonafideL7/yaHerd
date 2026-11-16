import Foundation
import Observation

/// Coordinates the Herd list with the authoritative, persisted app selection.
/// No item is selected from a cached list without refreshing store access first.
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

    func refresh(reportErrors: Bool = true) {
        do {
            herds = try repository.fetchAccessibleHerds()
            errorMessage = nil
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
        herds = accessible
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
