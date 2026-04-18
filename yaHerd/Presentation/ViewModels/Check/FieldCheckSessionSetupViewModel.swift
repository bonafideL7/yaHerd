import Foundation
import Observation

@MainActor
@Observable
final class FieldCheckSessionSetupViewModel {
    private(set) var pastures: [PastureOption] = []
    var errorMessage: String?

    func load(using repository: any FieldCheckRepository) {
        do {
            pastures = try repository.fetchPastureOptions()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSession(
        pastureID: UUID?,
        startedAt: Date,
        notes: String,
        using repository: any FieldCheckRepository
    ) throws -> UUID {
        guard let pastureID else {
            throw FieldCheckRepositoryError.pastureNotFound
        }

        let input = FieldCheckSessionStartInput(
            pastureID: pastureID,
            startedAt: startedAt,
            notes: notes
        )
        return try CreateFieldCheckSessionUseCase(repository: repository).execute(input: input)
    }
}
