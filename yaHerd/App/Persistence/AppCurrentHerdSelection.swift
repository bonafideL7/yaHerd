import Foundation
import Observation

/// The single application-wide Herd identity used by all repositories.
@MainActor
@Observable
final class AppCurrentHerdSelection: CurrentHerdSelectionReading {
    private(set) var currentHerdID: UUID?

    init(currentHerdID: UUID? = nil) {
        self.currentHerdID = currentHerdID
    }

    func select(_ herdID: UUID?) {
        currentHerdID = herdID
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
