import Foundation
import Observation

@MainActor
@Observable
final class AnimalDetailViewModel {
    private(set) var detail: AnimalDetailSnapshot?
    let form = AnimalFormViewModel()
    var isEditing = false
    var hasLoaded = false
    var errorMessage: String?
    var didDelete = false

    func load(animalID: UUID, using repository: any AnimalRepository) {
        defer { hasLoaded = true }

        form.loadSupportData(using: repository)

        do {
            let loadedDetail = try LoadAnimalDetailUseCase(repository: repository).execute(id: animalID)
            detail = loadedDetail
            if let loadedDetail, !isEditing {
                form.populate(from: loadedDetail)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginEditing() {
        guard let detail else { return }
        form.populate(from: detail)
        isEditing = true
    }

    func cancelEditing() {
        guard let detail else {
            isEditing = false
            return
        }
        form.populate(from: detail)
        isEditing = false
    }

    func save(animalID: UUID, using repository: any AnimalRepository) {
        do {
            let input = try form.makeInput()
            let updated = try UpdateAnimalUseCase(repository: repository).execute(id: animalID, input: input)
            self.detail = updated
            form.populate(from: updated)
            isEditing = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addTag(animalID: UUID, number: String, colorID: UUID?, isPrimary: Bool, using repository: any AnimalRepository) {
        do {
            let updated = try AddAnimalTagUseCase(repository: repository).execute(
                animalID: animalID,
                input: AnimalTagInput(number: number, colorID: colorID, isPrimary: isPrimary)
            )
            detail = updated
            form.syncPrimaryTag(from: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func promoteTag(animalID: UUID, tagID: UUID, using repository: any AnimalRepository) {
        do {
            let updated = try PromoteAnimalTagUseCase(repository: repository).execute(animalID: animalID, tagID: tagID)
            detail = updated
            form.syncPrimaryTag(from: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retireTag(animalID: UUID, tagID: UUID, using repository: any AnimalRepository) {
        do {
            let updated = try RetireAnimalTagUseCase(repository: repository).execute(animalID: animalID, tagID: tagID)
            detail = updated
            form.syncPrimaryTag(from: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func quickUpdateStatus(animalID: UUID, to status: AnimalStatus, using repository: any AnimalRepository) {
        guard let detail else { return }

        let input = AnimalInput(
            name: detail.name,
            tagNumber: detail.displayTagNumber,
            tagColorID: detail.displayTagColorID,
            sex: detail.sex,
            birthDate: detail.birthDate,
            status: status,
            pastureID: detail.pastureID,
            sire: detail.sire,
            dam: detail.dam,
            distinguishingFeatures: detail.distinguishingFeatures,
            saleDate: status == .sold ? .now : nil,
            salePrice: nil,
            reasonSold: nil,
            deathDate: status == .dead ? .now : nil,
            causeOfDeath: nil,
            statusReferenceID: nil
        )

        do {
            let updated = try UpdateAnimalUseCase(repository: repository).execute(id: animalID, input: input)
            self.detail = updated
            form.populate(from: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func archive(animalID: UUID, using repository: any AnimalRepository) {
        do {
            try ArchiveAnimalsUseCase(repository: repository).execute(ids: [animalID])
            load(animalID: animalID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore(animalID: UUID, using repository: any AnimalRepository) {
        do {
            try RestoreAnimalsUseCase(repository: repository).execute(ids: [animalID])
            load(animalID: animalID, using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(animalID: UUID, using repository: any AnimalRepository) {
        do {
            try DeleteAnimalsUseCase(repository: repository).execute(ids: [animalID])
            didDelete = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
