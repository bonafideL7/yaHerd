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
            let loadedDetail = try LoadFieldCheckDetailUseCase(repository: repository).execute(id: sessionID)
            detail = loadedDetail
            notesDraft = loadedDetail?.notes ?? ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(sessionID: UUID, using repository: any FieldCheckSessionDetailRepository) {
        do {
            let loadedDetail = try LoadFieldCheckDetailUseCase(repository: repository).execute(id: sessionID)
            detail = loadedDetail
            if let loadedDetail, notesDraft.trimmingCharacters(in: .whitespacesAndNewlines) == loadedDetail.notes.trimmingCharacters(in: .whitespacesAndNewlines) {
                notesDraft = loadedDetail.notes
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    func updateQuickAnimalTypeCounts(sessionID: UUID, counts: [AnimalType: Int], using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: counts)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.setAnimalCheckCounted(sessionID: sessionID, animalCheckID: animalCheckID, isCounted: isCounted)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.setAnimalCheckMissing(sessionID: sessionID, animalCheckID: animalCheckID, isMissing: isMissing)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addTrackedAnimalToSession(sessionID: UUID, animalID: UUID, using repository: any FieldCheckSessionDetailRepository) -> Bool {
        do {
            try repository.addTrackedAnimalToSession(sessionID: sessionID, animalID: animalID, checkedAt: .now)
            refresh(sessionID: sessionID, using: repository)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func addFinding(sessionID: UUID, input: FieldCheckFindingInput, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.addFinding(sessionID: sessionID, input: input)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateFinding(sessionID: UUID, findingID: UUID, input: FieldCheckFindingInput, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.updateFinding(sessionID: sessionID, findingID: findingID, input: input)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.updateFindingStatus(sessionID: sessionID, findingID: findingID, status: status)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteFinding(sessionID: UUID, findingID: UUID, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.deleteFinding(sessionID: sessionID, findingID: findingID)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeSession(sessionID: UUID, using repository: any FieldCheckSessionDetailRepository) {
        do {
            persistNotes(sessionID: sessionID, using: repository)
            try repository.completeSession(id: sessionID)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reopenSession(sessionID: UUID, using repository: any FieldCheckSessionDetailRepository) {
        do {
            try repository.reopenSession(id: sessionID)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
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
            animalDetail = try LoadAnimalDetailUseCase(repository: animalRepository).execute(id: animalID)
            preparedOffspringEditor = try PrepareOffspringDraftUseCase(repository: animalRepository).execute(forDamID: animalID)
            sessionDetail = try LoadFieldCheckDetailUseCase(repository: fieldCheckRepository).execute(id: sessionID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(
        animalID: UUID,
        sessionID: UUID,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) {
        do {
            animalDetail = try LoadAnimalDetailUseCase(repository: animalRepository).execute(id: animalID)
            preparedOffspringEditor = try PrepareOffspringDraftUseCase(repository: animalRepository).execute(forDamID: animalID)
            sessionDetail = try LoadFieldCheckDetailUseCase(repository: fieldCheckRepository).execute(id: sessionID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
        type: FieldCheckFindingType,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) {
        do {
            try fieldCheckRepository.addFinding(
                sessionID: sessionID,
                input: FieldCheckFindingInput(
                    recordedAt: dateProvider.now,
                    type: type,
                    severity: FieldCheckFindingRules.defaultSeverity(for: type),
                    status: .open,
                    note: "",
                    animalID: animalID
                )
            )
            refresh(
                animalID: animalID,
                sessionID: sessionID,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
@Observable
final class FieldCheckTrackedAnimalPickerViewModel {
    private(set) var animals: [AnimalSummary] = []
    var searchText = ""
    var errorMessage: String?
    var hasLoaded = false

    func load(using repository: any AnimalSummaryReading) {
        defer { hasLoaded = true }

        do {
            animals = try LoadAnimalsUseCase(repository: repository).execute()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func eligibleAnimals(
        forPastureID pastureID: UUID?,
        excluding checkedAnimalIDs: Set<UUID>
    ) -> [AnimalSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return animals
            .filter { animal in
                animal.status == .active
                    && !animal.isArchived
                    && animal.pastureID != pastureID
                    && !checkedAnimalIDs.contains(animal.id)
            }
            .filter { animal in
                guard !query.isEmpty else { return true }
                return animal.displayTagNumber.localizedCaseInsensitiveContains(query)
                    || animal.name.localizedCaseInsensitiveContains(query)
                    || (animal.pastureName?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { left, right in
                let lhs = left.displayTagNumber.isEmpty ? left.name : left.displayTagNumber
                let rhs = right.displayTagNumber.isEmpty ? right.name : right.displayTagNumber
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }
}
