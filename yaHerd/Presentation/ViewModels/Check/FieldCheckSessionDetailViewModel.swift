import Foundation
import Observation

@MainActor
@Observable
final class FieldCheckSessionDetailViewModel {
    private(set) var detail: FieldCheckSessionDetailSnapshot?
    var notesDraft = ""
    var errorMessage: String?
    var hasLoaded = false

    func load(sessionID: UUID, using repository: any FieldCheckSessionDetailRepository) {
        defer { hasLoaded = true }

        do {
            let loadedDetail = try repository.fetchSessionDetail(id: sessionID)
            detail = loadedDetail
            notesDraft = loadedDetail?.notes ?? ""
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func refresh(sessionID: UUID, using repository: any FieldCheckSessionDetailRepository) {
        do {
            let loadedDetail = try repository.fetchSessionDetail(id: sessionID)
            detail = loadedDetail
            if let loadedDetail, notesDraft.trimmingCharacters(in: .whitespacesAndNewlines) == loadedDetail.notes.trimmingCharacters(in: .whitespacesAndNewlines) {
                notesDraft = loadedDetail.notes
            }
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func persistNotes(sessionID: UUID, using repository: any FieldCheckSessionDetailRepository) {
        guard let detail else { return }
        let normalizedDraft = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSaved = detail.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedDraft != normalizedSaved else { return }

        do {
            try repository.updateNotes(sessionID: sessionID, notes: notesDraft)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func updateQuickAnimalTypeCounts(sessionID: UUID, counts: [AnimalType: Int], using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: counts)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.setAnimalCheckCounted(sessionID: sessionID, animalCheckID: animalCheckID, isCounted: isCounted)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.setAnimalCheckMissing(sessionID: sessionID, animalCheckID: animalCheckID, isMissing: isMissing)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func addTrackedAnimalToSession(sessionID: UUID, animalID: UUID, using repository: any FieldCheckSessionDetailRepository) -> Bool {
        do {
            try repository.addTrackedAnimalToSession(sessionID: sessionID, animalID: animalID, checkedAt: .now)
            refresh(sessionID: sessionID, using: repository)
            return true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }

    func addFinding(sessionID: UUID, input: FieldCheckFindingInput, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.addFinding(sessionID: sessionID, input: input)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func updateFinding(sessionID: UUID, findingID: UUID, input: FieldCheckFindingInput, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.updateFinding(sessionID: sessionID, findingID: findingID, input: input)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.updateFindingStatus(sessionID: sessionID, findingID: findingID, status: status)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func deleteFinding(sessionID: UUID, findingID: UUID, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.deleteFinding(sessionID: sessionID, findingID: findingID)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func completeSession(sessionID: UUID, using repository: any FieldCheckSessionDetailRepository) {
        do {
            persistNotes(sessionID: sessionID, using: repository)
            try repository.completeSession(id: sessionID)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func reopenSession(sessionID: UUID, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.reopenSession(id: sessionID)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}


@MainActor
@Observable
final class FieldCheckAnimalDetailViewModel {
    @ObservationIgnored private let dateProvider: any DateProviding
    private(set) var animalDetail: AnimalDetailSnapshot?
    private(set) var sessionDetail: FieldCheckSessionDetailSnapshot?
    var preparedOffspringEditor: PreparedAnimalEditor?
    var errorMessage: String?
    var hasLoaded = false

    var animalCheck: FieldCheckAnimalCheckSnapshot? {
        guard let animalID = animalDetail?.id else { return nil }
        return sessionDetail?.animalChecks.first(where: { $0.animalID == animalID })
    }

    var animalFindings: [FieldCheckFindingSnapshot] {
        guard let animalID = animalDetail?.id else { return [] }
        return (sessionDetail?.findings ?? [])
            .filter { $0.animalID == animalID }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    init(dateProvider: any DateProviding = SystemDateProvider()) {
        self.dateProvider = dateProvider
    }

    func load(
        animalID: UUID,
        sessionID: UUID,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) {
        defer { hasLoaded = true }

        do {
            animalDetail = try animalRepository.fetchAnimalDetail(id: animalID)
            preparedOffspringEditor = try PrepareOffspringDraftUseCase(repository: animalRepository).execute(forDamID: animalID)
            sessionDetail = try fieldCheckRepository.fetchSessionDetail(id: sessionID)
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func refresh(
        animalID: UUID,
        sessionID: UUID,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) {
        do {
            animalDetail = try animalRepository.fetchAnimalDetail(id: animalID)
            preparedOffspringEditor = try PrepareOffspringDraftUseCase(repository: animalRepository).execute(forDamID: animalID)
            sessionDetail = try fieldCheckRepository.fetchSessionDetail(id: sessionID)
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func setAnimalCheckCounted(
        animalID: UUID,
        sessionID: UUID,
        isCounted: Bool,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) {
        guard let animalCheckID = animalCheck?.id else { return }

        do {
            try fieldCheckRepository.setAnimalCheckCounted(sessionID: sessionID, animalCheckID: animalCheckID, isCounted: isCounted)
            refresh(animalID: animalID, sessionID: sessionID, animalRepository: animalRepository, fieldCheckRepository: fieldCheckRepository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func setAnimalCheckMissing(
        animalID: UUID,
        sessionID: UUID,
        isMissing: Bool,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) {
        guard let animalCheckID = animalCheck?.id else { return }

        do {
            try fieldCheckRepository.setAnimalCheckMissing(sessionID: sessionID, animalCheckID: animalCheckID, isMissing: isMissing)
            refresh(animalID: animalID, sessionID: sessionID, animalRepository: animalRepository, fieldCheckRepository: fieldCheckRepository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func addTrackedAnimalToSession(
        animalID: UUID,
        sessionID: UUID,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) throws {
        try fieldCheckRepository.addTrackedAnimalToSession(sessionID: sessionID, animalID: animalID, checkedAt: dateProvider.now)
    }

    func addFinding(
        animalID: UUID,
        sessionID: UUID,
        input: FieldCheckFindingInput,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) {
        do {
            try fieldCheckRepository.addFinding(sessionID: sessionID, input: input)
            refresh(
                animalID: animalID,
                sessionID: sessionID,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func updateFinding(
        animalID: UUID,
        sessionID: UUID,
        findingID: UUID,
        input: FieldCheckFindingInput,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) {
        do {
            try fieldCheckRepository.updateFinding(sessionID: sessionID, findingID: findingID, input: input)
            refresh(animalID: animalID, sessionID: sessionID, animalRepository: animalRepository, fieldCheckRepository: fieldCheckRepository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func updateFindingStatus(
        animalID: UUID,
        sessionID: UUID,
        findingID: UUID,
        status: FieldCheckFindingStatus,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) {
        do {
            try fieldCheckRepository.updateFindingStatus(sessionID: sessionID, findingID: findingID, status: status)
            refresh(animalID: animalID, sessionID: sessionID, animalRepository: animalRepository, fieldCheckRepository: fieldCheckRepository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func deleteFinding(
        animalID: UUID,
        sessionID: UUID,
        findingID: UUID,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) {
        do {
            try fieldCheckRepository.deleteFinding(sessionID: sessionID, findingID: findingID)
            refresh(
                animalID: animalID,
                sessionID: sessionID,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }
}

@MainActor
@Observable
final class FieldCheckTrackedAnimalPickerViewModel {
    private(set) var animals: [AnimalSummary] = []
    var errorMessage: String?
    var hasLoaded = false

    func load(using repository: any AnimalSummaryReading) {
        defer { hasLoaded = true }

        do {
            animals = try repository.fetchAnimals()
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

}
