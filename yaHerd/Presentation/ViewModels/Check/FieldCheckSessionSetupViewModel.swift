import Foundation
import Observation

@MainActor
@Observable
final class FieldCheckSessionSetupViewModel {
    private(set) var pastures: [PastureOption] = []
    var errorMessage: String?
    var hasLoaded = false

    func load(using repository: any PastureReferenceDataReader) {
        defer { hasLoaded = true }

        do {
            pastures = try repository.fetchPastureOptions()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func createSession(
        pastureID: UUID?,
        startedAt: Date,
        notes: String,
        originatingHerdID: UUID,
        currentHerdSelection: any CurrentHerdSelectionReading,
        using repository: any FieldCheckSessionCreating
    ) async throws -> UUID? {
        guard let pastureID else {
            throw FieldCheckRepositoryError.pastureNotFound
        }
        // An obsolete setup must not start a write in a newly selected Herd.
        guard !Task.isCancelled,
              currentHerdSelection.currentHerdID == originatingHerdID else {
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
              currentHerdSelection.currentHerdID == originatingHerdID else {
            return nil
        }
        return sessionID
    }
}
