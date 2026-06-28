import Foundation
import Observation

enum AnimalEditorScrollTarget: Hashable {
    case status
}

@MainActor
@Observable
final class AnimalDetailViewModel {
    private(set) var detail: AnimalDetailSnapshot?
    let form = AnimalFormViewModel()
    var draftTags: [AnimalTagSnapshot] = []
    var isEditing = false
    var hasLoaded = false
    var errorMessage: String?
    var didDelete = false
    var pendingScrollTarget: AnimalEditorScrollTarget?
    var preparedOffspringEditor: PreparedAnimalEditor?

    func load(
        animalID: UUID,
        using repository: any AnimalRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        defer { hasLoaded = true }

        form.loadSupportData(using: repository, pastureRepository: pastureRepository)

        do {
            let loadedDetail = try LoadAnimalDetailUseCase(repository: repository).execute(id: animalID)
            detail = loadedDetail
            preparedOffspringEditor = try PrepareOffspringDraftUseCase(repository: repository).execute(forDamID: animalID)
            if let loadedDetail, !isEditing {
                form.populate(from: loadedDetail)
                draftTags = loadedDetail.activeTags + loadedDetail.inactiveTags
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginEditing() {
        guard let detail else { return }
        form.populate(from: detail)
        draftTags = detail.activeTags + detail.inactiveTags
        pendingScrollTarget = nil
        isEditing = true
    }

    func cancelEditing() {
        guard let detail else {
            draftTags = []
            pendingScrollTarget = nil
            isEditing = false
            return
        }
        form.populate(from: detail)
        draftTags = detail.activeTags + detail.inactiveTags
        pendingScrollTarget = nil
        isEditing = false
    }

    func save(animalID: UUID, defaultTagColorID: UUID?, using repository: any AnimalRepository) {
        guard detail != nil else { return }

        do {
            let input = try form.makeInput(defaultTagColorID: defaultTagColorID)
            let updated = try UpdateAnimalWithTagsUseCase(repository: repository).execute(
                animalID: animalID,
                input: input,
                desiredTags: draftTags,
                defaultTagColorID: defaultTagColorID
            )

            detail = updated
            form.populate(from: updated)
            draftTags = updated.activeTags + updated.inactiveTags
            pendingScrollTarget = nil
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

    func updateTag(animalID: UUID, tagID: UUID, number: String, colorID: UUID?, isPrimary: Bool, using repository: any AnimalRepository) {
        do {
            let updated = try UpdateAnimalTagUseCase(repository: repository).execute(
                animalID: animalID,
                tagID: tagID,
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


    func addDraftTag(number: String, colorID: UUID?, isPrimary: Bool) {
        draftTags = AnimalTagDraftEditor.addTag(
            to: draftTags,
            number: number,
            colorID: colorID,
            isPrimary: isPrimary
        )
        syncDraftPrimaryTagToForm()
    }

    func updateDraftTag(tagID: UUID, number: String, colorID: UUID?, isPrimary: Bool) {
        draftTags = AnimalTagDraftEditor.updateTag(
            in: draftTags,
            tagID: tagID,
            number: number,
            colorID: colorID,
            isPrimary: isPrimary
        )
        syncDraftPrimaryTagToForm()
    }

    func promoteDraftTag(tagID: UUID) {
        draftTags = AnimalTagDraftEditor.promoteTag(in: draftTags, tagID: tagID)
        syncDraftPrimaryTagToForm()
    }

    func retireDraftTag(tagID: UUID) {
        let originalIDs = Set((detail?.activeTags ?? []).map(\.id) + (detail?.inactiveTags ?? []).map(\.id))
        draftTags = AnimalTagDraftEditor.retireTag(in: draftTags, tagID: tagID, persistedTagIDs: originalIDs)
        syncDraftPrimaryTagToForm()
    }

    private func syncDraftPrimaryTagToForm() {
        if let primary = AnimalTagDraftEditor.primaryTag(in: draftTags) {
            form.draft.tagNumber = primary.normalizedNumber
            form.draft.tagColorID = primary.colorID
        } else {
            form.draft.tagNumber = ""
            form.draft.tagColorID = nil
        }
    }

    var canAddOffspring: Bool {
        guard let detail else { return false }
        return detail.sex == .female && !detail.isArchived && detail.status == .active
    }

    func beginEditingStatus(_ status: AnimalStatus? = nil) {
        guard let detail else { return }

        form.populate(from: detail)
        draftTags = detail.activeTags + detail.inactiveTags

        if let status {
            form.draft.status = status
            form.draft.statusReferenceID = nil

            switch status {
            case .active:
                break
            case .sold:
                if detail.status != .sold {
                    form.draft.saleDate = .now
                    form.draft.salePriceText = ""
                    form.draft.reasonSold = ""
                }
            case .dead:
                if detail.status != .dead {
                    form.draft.deathDate = .now
                    form.draft.causeOfDeath = ""
                }
            }
        }

        pendingScrollTarget = .status
        isEditing = true
    }

    func archive(
        animalID: UUID,
        using repository: any AnimalRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        do {
            try ArchiveAnimalsUseCase(repository: repository).execute(ids: [animalID])
            load(animalID: animalID, using: repository, pastureRepository: pastureRepository)
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
            load(animalID: animalID, using: repository, pastureRepository: pastureRepository)
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
