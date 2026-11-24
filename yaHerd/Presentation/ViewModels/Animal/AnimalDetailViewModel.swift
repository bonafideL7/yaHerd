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

    @ObservationIgnored private var editingHerdID: UUID?
    @ObservationIgnored private var editingSelectionRevision: UInt64?
    @ObservationIgnored private var viewingHerdID: UUID?
    @ObservationIgnored private var viewingSelectionRevision: UInt64?
    @ObservationIgnored private var hasCapturedViewingSelection = false

    func captureViewingSelection(_ selection: AppCurrentHerdSelection) {
        guard !hasCapturedViewingSelection else { return }
        hasCapturedViewingSelection = true
        viewingHerdID = selection.currentHerdID
        viewingSelectionRevision = selection.selectionRevision
    }

    func isViewingSelectionCurrent(_ selection: AppCurrentHerdSelection) -> Bool {
        guard let viewingHerdID, let viewingSelectionRevision else { return false }
        return selection.currentHerdID == viewingHerdID
            && selection.selectionRevision == viewingSelectionRevision
    }

    /// Retained detail views may not present a record from an obsolete Herd selection.
    func presentationDetail(for selection: AppCurrentHerdSelection) -> AnimalDetailSnapshot? {
        guard isViewingSelectionCurrent(selection) else { return nil }
        return detail
    }

    var viewingSelectionIdentity: (herdID: UUID, revision: UInt64)? {
        guard let viewingHerdID, let viewingSelectionRevision else { return nil }
        return (viewingHerdID, viewingSelectionRevision)
    }

    private func validateViewingSelection(_ selection: AppCurrentHerdSelection) -> Bool {
        guard isViewingSelectionCurrent(selection) else {
            errorMessage = "The selected Herd changed. Reopen this animal before making changes."
            return false
        }
        return true
    }

    func load(
        animalID: UUID,
        using repository: any AnimalDetailRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        defer { hasLoaded = true }

        form.loadSupportData(using: repository, pastureRepository: pastureRepository)

        do {
            let loadedDetail = try repository.fetchAnimalDetail(id: animalID)
            detail = loadedDetail
            preparedOffspringEditor = try PrepareOffspringDraftUseCase(repository: repository).execute(forDamID: animalID)
            if let loadedDetail, !isEditing {
                form.populate(from: loadedDetail)
                draftTags = loadedDetail.activeTags + loadedDetail.inactiveTags
            }
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func beginEditing(selection: AppCurrentHerdSelection) {
        guard validateViewingSelection(selection),
              let detail, let herdID = selection.currentHerdID else { return }
        editingHerdID = herdID
        editingSelectionRevision = selection.selectionRevision
        form.populate(from: detail)
        draftTags = detail.activeTags + detail.inactiveTags
        pendingScrollTarget = nil
        isEditing = true
    }

    func cancelEditing() {
        editingHerdID = nil
        editingSelectionRevision = nil
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

    func save(
        animalID: UUID,
        defaultTagColorID: UUID?,
        using repository: any AnimalDetailRepository,
        selection: AppCurrentHerdSelection
    ) {
        guard isEditing,
              detail?.id == animalID,
              let editingHerdID,
              let editingSelectionRevision,
              selection.currentHerdID == editingHerdID,
              selection.selectionRevision == editingSelectionRevision else {
            errorMessage = "The selected Herd or animal changed. Reopen the editor before saving."
            return
        }

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
            self.editingHerdID = nil
            self.editingSelectionRevision = nil
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func addTag(animalID: UUID, number: String, colorID: UUID?, isPrimary: Bool, using repository: any AnimalDetailRepository) {
        do {
            let updated = try repository.addTag(
                animalID: animalID,
                input: AnimalTagInput(number: number, colorID: colorID, isPrimary: isPrimary)
            )
            detail = updated
            form.syncPrimaryTag(from: updated)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func updateTag(animalID: UUID, tagID: UUID, number: String, colorID: UUID?, isPrimary: Bool, using repository: any AnimalDetailRepository) {
        do {
            let updated = try repository.updateTag(
                animalID: animalID,
                tagID: tagID,
                input: AnimalTagInput(number: number, colorID: colorID, isPrimary: isPrimary)
            )
            detail = updated
            form.syncPrimaryTag(from: updated)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func promoteTag(animalID: UUID, tagID: UUID, using repository: any AnimalDetailRepository) {
        do {
            let updated = try repository.promoteTag(animalID: animalID, tagID: tagID)
            detail = updated
            form.syncPrimaryTag(from: updated)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func retireTag(animalID: UUID, tagID: UUID, using repository: any AnimalDetailRepository) {
        do {
            let updated = try repository.retireTag(animalID: animalID, tagID: tagID)
            detail = updated
            form.syncPrimaryTag(from: updated)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
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

    func beginEditingStatus(
        _ status: AnimalStatus? = nil,
        selection: AppCurrentHerdSelection
    ) {
        guard validateViewingSelection(selection),
              let detail, let herdID = selection.currentHerdID else { return }
        editingHerdID = herdID
        editingSelectionRevision = selection.selectionRevision
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
        using repository: any AnimalDetailRepository,
        pastureRepository: any PastureReferenceDataReader,
        selection: AppCurrentHerdSelection
    ) {
        guard validateViewingSelection(selection) else { return }
        do {
            try repository.archive(ids: [animalID])
            load(animalID: animalID, using: repository, pastureRepository: pastureRepository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func restore(
        animalID: UUID,
        using repository: any AnimalDetailRepository,
        pastureRepository: any PastureReferenceDataReader,
        selection: AppCurrentHerdSelection
    ) {
        guard validateViewingSelection(selection) else { return }
        do {
            try repository.restore(ids: [animalID])
            load(animalID: animalID, using: repository, pastureRepository: pastureRepository)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func preparePermanentDeleteReview(
        animalID: UUID,
        using repository: any AnimalDetailRepository,
        selection: AppCurrentHerdSelection
    ) -> AnimalDetailSnapshot? {
        guard validateViewingSelection(selection) else { return nil }
        do {
            let currentDetail = try fetchArchivedDetail(animalID: animalID, using: repository)
            detail = currentDetail
            errorMessage = nil
            return currentDetail
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return nil
        }
    }

    func delete(
        animalID: UUID,
        using repository: any AnimalDetailRepository,
        selection: AppCurrentHerdSelection
    ) {
        guard validateViewingSelection(selection) else { return }
        do {
            _ = try fetchArchivedDetail(animalID: animalID, using: repository)
            try repository.delete(ids: [animalID])
            didDelete = true
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    private func fetchArchivedDetail(
        animalID: UUID,
        using repository: any AnimalDetailRepository
    ) throws -> AnimalDetailSnapshot {
        guard let currentDetail = try repository.fetchAnimalDetail(id: animalID) else {
            throw AnimalValidationError.animalNotFound
        }
        guard currentDetail.isArchived else {
            throw AnimalValidationError.permanentDeleteRequiresArchive
        }
        return currentDetail
    }
}
