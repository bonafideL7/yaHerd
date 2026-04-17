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
            refresh(sessionID: sessionID, using: repository)
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
        do {
            try repository.deleteFinding(sessionID: sessionID, findingID: findingID)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addNewborn(sessionID: UUID, input: FieldCheckNewbornInput, using repository: any FieldCheckRepository) {
        do {
            try repository.addNewborn(sessionID: sessionID, input: input)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteNewborn(sessionID: UUID, newbornID: UUID, using repository: any FieldCheckRepository) {
        do {
            try repository.deleteNewborn(sessionID: sessionID, newbornID: newbornID)
            refresh(sessionID: sessionID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func convertNewbornToAnimal(sessionID: UUID, newbornID: UUID, using repository: any FieldCheckRepository) -> UUID? {
        do {
            let animalID = try repository.convertNewbornToAnimal(sessionID: sessionID, newbornID: newbornID)
            refresh(sessionID: sessionID, using: repository)
            return animalID
        } catch {
            errorMessage = error.localizedDescription
            return nil
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
}
