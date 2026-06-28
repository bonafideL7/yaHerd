import Foundation
import Observation

@MainActor
@Observable
final class AnimalListViewModel {
    private(set) var items: [AnimalSummary] = []
    private(set) var pastureOptions: [PastureOption] = []
    var errorMessage: String?

    func load(
        using repository: any AnimalRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        do {
            items = try LoadAnimalsUseCase(repository: repository).execute()
            pastureOptions = try LoadPastureOptionsUseCase(repository: pastureRepository).execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func performPrimarySwipeAction(
        animalID: UUID,
        hardDelete: Bool,
        using repository: any AnimalRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        do {
            if hardDelete {
                try DeleteAnimalsUseCase(repository: repository).execute(ids: [animalID])
            } else {
                try ArchiveAnimalsUseCase(repository: repository).execute(ids: [animalID])
            }
            load(using: repository, pastureRepository: pastureRepository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore(
        animalID: UUID,
        using repository: any AnimalRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        do {
            try RestoreAnimalsUseCase(repository: repository).execute(ids: [animalID])
            load(using: repository, pastureRepository: pastureRepository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(
        ids: [UUID],
        toPastureID pastureID: UUID?,
        using repository: any AnimalRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        do {
            try MoveAnimalsUseCase(repository: repository).execute(ids: ids, toPastureID: pastureID)
            load(using: repository, pastureRepository: pastureRepository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pastureName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return pastureOptions.first(where: { $0.id == id })?.name
    }
}
