import Foundation
import Observation

@MainActor
@Observable
final class FieldCheckSessionDetailViewModel {
    private(set) var detail: FieldCheckSessionDetailSnapshot?
    var notesDraft = ""
    var errorMessage: String?
    var hasLoaded = false

    func load(sessionID: UUID, using repository: any FieldCheckRepository) {
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

    func refresh(sessionID: UUID, using repository: any FieldCheckRepository) {
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

    func persistNotes(sessionID: UUID, using repository: any FieldCheckRepository) {
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

    func updateQuickCounts(sessionID: UUID, quickTaggedCount: Int, quickUntaggedCount: Int, using repository: any FieldCheckRepository) {
        do {
            try repository.updateQuickCounts(
                sessionID: sessionID,
                quickTaggedCount: quickTaggedCount,
                quickUntaggedCount: quickUntaggedCount
            )
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAnimalCheckCounted(sessionID: UUID, animalCheckID: UUID, isCounted: Bool, using repository: any FieldCheckRepository) {
        do {
            try repository.setAnimalCheckCounted(sessionID: sessionID, animalCheckID: animalCheckID, isCounted: isCounted)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAnimalCheckNeedsAttention(sessionID: UUID, animalCheckID: UUID, needsAttention: Bool, using repository: any FieldCheckRepository) {
        do {
            try repository.setAnimalCheckNeedsAttention(sessionID: sessionID, animalCheckID: animalCheckID, needsAttention: needsAttention)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAnimalCheckMissing(sessionID: UUID, animalCheckID: UUID, isMissing: Bool, using repository: any FieldCheckRepository) {
        do {
            try repository.setAnimalCheckMissing(sessionID: sessionID, animalCheckID: animalCheckID, isMissing: isMissing)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addFinding(sessionID: UUID, input: FieldCheckFindingInput, using repository: any FieldCheckRepository) {
        do {
            try repository.addFinding(sessionID: sessionID, input: input)
            if let animalID = input.animalID {
                try syncNeedsAttention(sessionID: sessionID, animalID: animalID, using: repository)
            } else {
                refresh(sessionID: sessionID, using: repository)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateFindingStatus(sessionID: UUID, findingID: UUID, status: FieldCheckFindingStatus, using repository: any FieldCheckRepository) {
        do {
            try repository.updateFindingStatus(sessionID: sessionID, findingID: findingID, status: status)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteFinding(sessionID: UUID, findingID: UUID, using repository: any FieldCheckRepository) {
        let animalID = detail?.findings.first(where: { $0.id == findingID })?.animalID

        do {
            try repository.deleteFinding(sessionID: sessionID, findingID: findingID)
            if let animalID {
                try syncNeedsAttention(sessionID: sessionID, animalID: animalID, using: repository)
            } else {
                refresh(sessionID: sessionID, using: repository)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeSession(sessionID: UUID, using repository: any FieldCheckRepository) {
        do {
            persistNotes(sessionID: sessionID, using: repository)
            try repository.completeSession(id: sessionID)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reopenSession(sessionID: UUID, using repository: any FieldCheckRepository) {
        do {
            try repository.reopenSession(id: sessionID)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncNeedsAttention(sessionID: UUID, animalID: UUID, using repository: any FieldCheckRepository) throws {
        let refreshedDetail = try LoadFieldCheckDetailUseCase(repository: repository).execute(id: sessionID)
        detail = refreshedDetail
        if let refreshedDetail, notesDraft.trimmingCharacters(in: .whitespacesAndNewlines) == refreshedDetail.notes.trimmingCharacters(in: .whitespacesAndNewlines) {
            notesDraft = refreshedDetail.notes
        }

        guard
            let animalCheck = refreshedDetail?.animalChecks.first(where: { $0.animalID == animalID })
        else {
            return
        }

        let shouldNeedAttention = refreshedDetail?.findings.contains(where: { $0.animalID == animalID }) ?? false
        if animalCheck.needsAttention != shouldNeedAttention {
            try repository.setAnimalCheckNeedsAttention(
                sessionID: sessionID,
                animalCheckID: animalCheck.id,
                needsAttention: shouldNeedAttention
            )
            refresh(sessionID: sessionID, using: repository)
        } else {
            errorMessage = nil
        }
    }
}


@MainActor
@Observable
final class FieldCheckAnimalDetailViewModel {
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

    func load(
        animalID: UUID,
        sessionID: UUID,
        animalRepository: any AnimalRepository,
        fieldCheckRepository: any FieldCheckRepository
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
        animalRepository: any AnimalRepository,
        fieldCheckRepository: any FieldCheckRepository
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
        animalRepository: any AnimalRepository,
        fieldCheckRepository: any FieldCheckRepository
    ) {
        guard let animalCheckID = animalCheck?.id else { return }

        do {
            try fieldCheckRepository.setAnimalCheckCounted(sessionID: sessionID, animalCheckID: animalCheckID, isCounted: isCounted)
            refresh(animalID: animalID, sessionID: sessionID, animalRepository: animalRepository, fieldCheckRepository: fieldCheckRepository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAnimalCheckNeedsAttention(
        animalID: UUID,
        sessionID: UUID,
        needsAttention: Bool,
        animalRepository: any AnimalRepository,
        fieldCheckRepository: any FieldCheckRepository
    ) {
        guard let animalCheckID = animalCheck?.id else { return }

        do {
            try fieldCheckRepository.setAnimalCheckNeedsAttention(sessionID: sessionID, animalCheckID: animalCheckID, needsAttention: needsAttention)
            refresh(animalID: animalID, sessionID: sessionID, animalRepository: animalRepository, fieldCheckRepository: fieldCheckRepository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAnimalCheckMissing(
        animalID: UUID,
        sessionID: UUID,
        isMissing: Bool,
        animalRepository: any AnimalRepository,
        fieldCheckRepository: any FieldCheckRepository
    ) {
        guard let animalCheckID = animalCheck?.id else { return }

        do {
            try fieldCheckRepository.setAnimalCheckMissing(sessionID: sessionID, animalCheckID: animalCheckID, isMissing: isMissing)
            refresh(animalID: animalID, sessionID: sessionID, animalRepository: animalRepository, fieldCheckRepository: fieldCheckRepository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addFinding(
        animalID: UUID,
        sessionID: UUID,
        type: FieldCheckFindingType,
        animalRepository: any AnimalRepository,
        fieldCheckRepository: any FieldCheckRepository
    ) {
        do {
            try fieldCheckRepository.addFinding(
                sessionID: sessionID,
                input: FieldCheckFindingInput(
                    recordedAt: .now,
                    type: type,
                    severity: defaultSeverity(for: type),
                    status: .open,
                    note: "",
                    animalID: animalID
                )
            )
            try syncNeedsAttention(
                animalID: animalID,
                sessionID: sessionID,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateFindingStatus(
        animalID: UUID,
        sessionID: UUID,
        findingID: UUID,
        status: FieldCheckFindingStatus,
        animalRepository: any AnimalRepository,
        fieldCheckRepository: any FieldCheckRepository
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
        animalRepository: any AnimalRepository,
        fieldCheckRepository: any FieldCheckRepository
    ) {
        do {
            try fieldCheckRepository.deleteFinding(sessionID: sessionID, findingID: findingID)
            try syncNeedsAttention(
                animalID: animalID,
                sessionID: sessionID,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncNeedsAttention(
        animalID: UUID,
        sessionID: UUID,
        animalRepository: any AnimalRepository,
        fieldCheckRepository: any FieldCheckRepository
    ) throws {
        let refreshedSessionDetail = try LoadFieldCheckDetailUseCase(repository: fieldCheckRepository).execute(id: sessionID)
        sessionDetail = refreshedSessionDetail

        guard
            let animalCheck = refreshedSessionDetail?.animalChecks.first(where: { $0.animalID == animalID })
        else {
            refresh(animalID: animalID, sessionID: sessionID, animalRepository: animalRepository, fieldCheckRepository: fieldCheckRepository)
            return
        }

        let shouldNeedAttention = refreshedSessionDetail?.findings.contains(where: { $0.animalID == animalID }) ?? false
        if animalCheck.needsAttention != shouldNeedAttention {
            try fieldCheckRepository.setAnimalCheckNeedsAttention(
                sessionID: sessionID,
                animalCheckID: animalCheck.id,
                needsAttention: shouldNeedAttention
            )
        }

        refresh(animalID: animalID, sessionID: sessionID, animalRepository: animalRepository, fieldCheckRepository: fieldCheckRepository)
    }

    private func defaultSeverity(for type: FieldCheckFindingType) -> FieldCheckFindingSeverity {
        switch type {
        case .injury, .medicalAttention, .calvingInProgress:
            return .critical
        case .pinkEye, .limping, .missingAnimal, .waterIssue, .fenceIssue:
            return .warning
        default:
            return .info
        }
    }
}
