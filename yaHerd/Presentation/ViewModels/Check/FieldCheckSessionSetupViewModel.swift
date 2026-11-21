import Foundation
import Observation

@MainActor
@Observable
final class FieldCheckSessionSetupViewModel {
    private(set) var pastures: [PastureOption] = []
    var errorMessage: String?
    var hasLoaded = false

    @ObservationIgnored private var selection: AppCurrentHerdSelection?
    @ObservationIgnored private var selectedHerdID: UUID?
    @ObservationIgnored private var selectedRevision: UInt64?

    var hasCurrentHerdData: Bool {
        hasLoaded && isCurrentSelection
    }

    func configure(selection: AppCurrentHerdSelection) {
        let changed = self.selection !== selection
            || selectedHerdID != selection.currentHerdID
            || selectedRevision != selection.selectionRevision
        self.selection = selection
        selectedHerdID = selection.currentHerdID
        selectedRevision = selection.selectionRevision

        if changed {
            pastures = []
            errorMessage = nil
            hasLoaded = false
        }
    }

    @discardableResult
    func load(using repository: any PastureReferenceDataReader) -> Bool {
        guard isCurrentSelection else { return false }
        defer { hasLoaded = true }

        do {
            pastures = try repository.fetchPastureOptions()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            errorMessage = nil
            return true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }

    private var isCurrentSelection: Bool {
        guard let selection, let selectedHerdID else { return false }
        return selectedHerdID == selection.currentHerdID
            && selectedRevision == selection.selectionRevision
    }

    func createSession(
        pastureID: UUID?,
        startedAt: Date,
        notes: String,
        originatingHerdID: UUID,
        currentHerdSelection: any CurrentHerdSelectionReading,
        selectionIsUnchanged: @escaping @MainActor () -> Bool,
        using repository: any FieldCheckSessionCreating
    ) async throws -> UUID? {
        guard let pastureID else {
            throw FieldCheckRepositoryError.pastureNotFound
        }
        // An obsolete setup must not start a write in a newly selected Herd.
        guard !Task.isCancelled,
              currentHerdSelection.currentHerdID == originatingHerdID,
              selectionIsUnchanged() else {
            return nil
        }

        let input = FieldCheckSessionStartInput(
            pastureID: pastureID,
            startedAt: startedAt,
            notes: notes
        )
        // The Core Data repository pins its Herd before awaiting the write gate.
        let sessionID = try await repository.createSession(input: input)

        // The original save may have committed even after the view was removed.
        // Never navigate to that record from another Herd's application state.
        guard !Task.isCancelled,
              currentHerdSelection.currentHerdID == originatingHerdID,
              selectionIsUnchanged() else {
            return nil
        }
        return sessionID
    }
}
