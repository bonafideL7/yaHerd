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

    func load(animalID: UUID, using repository: any AnimalRepository) {
        defer { hasLoaded = true }

        form.loadSupportData(using: repository)

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

    func save(animalID: UUID, using repository: any AnimalRepository) {
        guard detail != nil else { return }

        do {
            let input = try form.makeInput()
            var updated = try UpdateAnimalUseCase(repository: repository).execute(id: animalID, input: input)

            let desiredTags = draftTags
            var currentTagsByID = Dictionary(uniqueKeysWithValues: (updated.activeTags + updated.inactiveTags).map { ($0.id, $0) })

            let existingDesiredTags = desiredTags.filter { currentTagsByID[$0.id] != nil }
            let activeExistingNonPrimaryTags = existingDesiredTags.filter { $0.isActive && !$0.isPrimary }
            let inactiveExistingTags = existingDesiredTags.filter { !$0.isActive }
            let activeExistingPrimaryTags = existingDesiredTags.filter { $0.isActive && $0.isPrimary }

            for tag in activeExistingNonPrimaryTags {
                updated = try UpdateAnimalTagUseCase(repository: repository).execute(
                    animalID: animalID,
                    tagID: tag.id,
                    input: AnimalTagInput(number: tag.normalizedNumber, colorID: tag.colorID, isPrimary: false)
                )
            }

            for tag in inactiveExistingTags {
                updated = try UpdateAnimalTagUseCase(repository: repository).execute(
                    animalID: animalID,
                    tagID: tag.id,
                    input: AnimalTagInput(number: tag.normalizedNumber, colorID: tag.colorID, isPrimary: false)
                )
            }

            for tag in activeExistingPrimaryTags {
                updated = try UpdateAnimalTagUseCase(repository: repository).execute(
                    animalID: animalID,
                    tagID: tag.id,
                    input: AnimalTagInput(number: tag.normalizedNumber, colorID: tag.colorID, isPrimary: true)
                )
            }

            currentTagsByID = Dictionary(uniqueKeysWithValues: (updated.activeTags + updated.inactiveTags).map { ($0.id, $0) })
            for tag in inactiveExistingTags where currentTagsByID[tag.id]?.isActive == true {
                updated = try RetireAnimalTagUseCase(repository: repository).execute(animalID: animalID, tagID: tag.id)
            }

            let currentTags = updated.activeTags + updated.inactiveTags
            let newActiveTags = desiredTags.filter { currentTagsByID[$0.id] == nil && $0.isActive }
            for tag in newActiveTags.filter({ !$0.isPrimary }) {
                updated = try AddAnimalTagUseCase(repository: repository).execute(
                    animalID: animalID,
                    input: AnimalTagInput(number: tag.normalizedNumber, colorID: tag.colorID, isPrimary: false)
                )
            }

            let refreshedCurrentTags = updated.activeTags + updated.inactiveTags
            for tag in newActiveTags.filter({ $0.isPrimary }) {
                let alreadyRepresented = refreshedCurrentTags.contains { existing in
                    existing.isActive
                        && existing.isPrimary
                        && existing.normalizedNumber == tag.normalizedNumber
                        && existing.colorID == tag.colorID
                }

                if !alreadyRepresented {
                    updated = try AddAnimalTagUseCase(repository: repository).execute(
                        animalID: animalID,
                        input: AnimalTagInput(number: tag.normalizedNumber, colorID: tag.colorID, isPrimary: true)
                    )
                }
            }

            self.detail = updated
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
        let normalizedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNumber.isEmpty else { return }

        let shouldBePrimary = isPrimary || draftTags.filter(\.isActive).isEmpty

        if shouldBePrimary {
            draftTags = draftTags.map { tag in
                AnimalTagSnapshot(
                    id: tag.id,
                    number: tag.number,
                    colorID: tag.colorID,
                    isPrimary: false,
                    isActive: tag.isActive,
                    assignedAt: tag.assignedAt,
                    removedAt: tag.removedAt
                )
            }
        }

        draftTags.append(
            AnimalTagSnapshot(
                id: UUID(),
                number: normalizedNumber,
                colorID: colorID,
                isPrimary: shouldBePrimary,
                isActive: true,
                assignedAt: .now,
                removedAt: nil
            )
        )

        syncDraftPrimaryTagToForm()
    }

    func updateDraftTag(tagID: UUID, number: String, colorID: UUID?, isPrimary: Bool) {
        let normalizedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNumber.isEmpty else { return }

        let shouldBePrimary = isPrimary || draftTags.filter { $0.id != tagID && $0.isActive }.isEmpty

        draftTags = draftTags.map { tag in
            AnimalTagSnapshot(
                id: tag.id,
                number: tag.id == tagID ? normalizedNumber : tag.number,
                colorID: tag.id == tagID ? colorID : tag.colorID,
                isPrimary: tag.id == tagID ? (tag.isActive ? shouldBePrimary : false) : ((shouldBePrimary && tag.isActive) ? false : tag.isPrimary),
                isActive: tag.isActive,
                assignedAt: tag.assignedAt,
                removedAt: tag.removedAt
            )
        }

        syncDraftPrimaryTagToForm()
    }

    func promoteDraftTag(tagID: UUID) {
        draftTags = draftTags.map { tag in
            AnimalTagSnapshot(
                id: tag.id,
                number: tag.number,
                colorID: tag.colorID,
                isPrimary: tag.id == tagID,
                isActive: tag.isActive,
                assignedAt: tag.assignedAt,
                removedAt: tag.removedAt
            )
        }
        syncDraftPrimaryTagToForm()
    }

    func retireDraftTag(tagID: UUID) {
        let originalIDs = Set((detail?.activeTags ?? []).map(\.id) + (detail?.inactiveTags ?? []).map(\.id))

        if !originalIDs.contains(tagID) {
            draftTags.removeAll { $0.id == tagID }
        } else {
            draftTags = draftTags.map { tag in
                guard tag.id == tagID else { return tag }
                return AnimalTagSnapshot(
                    id: tag.id,
                    number: tag.number,
                    colorID: tag.colorID,
                    isPrimary: false,
                    isActive: false,
                    assignedAt: tag.assignedAt,
                    removedAt: tag.removedAt ?? .now
                )
            }
        }

        if !draftTags.contains(where: { $0.isActive && $0.isPrimary }), let firstActiveID = draftTags.first(where: { $0.isActive })?.id {
            promoteDraftTag(tagID: firstActiveID)
        } else {
            syncDraftPrimaryTagToForm()
        }
    }

    private func syncDraftPrimaryTagToForm() {
        if let primary = draftTags.first(where: { $0.isActive && $0.isPrimary }) {
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
