import Foundation
import Observation

@MainActor
@Observable
final class AddAnimalViewModel {
    let form: AnimalFormViewModel
    var pendingTags: [AnimalTagSnapshot] = []
    var errorMessage: String?

    init(initialDraft: AnimalEditorDraft = AnimalEditorDraft(), editorContext: AnimalEditorContext = .standard) {
        form = AnimalFormViewModel(draft: initialDraft, context: editorContext)
    }

    func loadSupportData(
        using animalRepository: any AnimalRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        form.loadSupportData(using: animalRepository, pastureRepository: pastureRepository)
    }

    func save(defaultTagColorID: UUID?, using repository: any AnimalRepository) throws {
        let input = try form.makeInput(defaultTagColorID: defaultTagColorID)
        _ = try CreateAnimalWithTagsUseCase(repository: repository).execute(
            input: input,
            tags: pendingTags,
            defaultTagColorID: defaultTagColorID
        )
    }

    func addPendingTag(number: String, colorID: UUID?, isPrimary: Bool, defaultTagColorID: UUID?) {
        pendingTags = AnimalTagDraftEditor.addTag(
            to: pendingTags,
            number: number,
            colorID: resolvedColorID(number: number, colorID: colorID, defaultTagColorID: defaultTagColorID),
            isPrimary: isPrimary
        )
        syncPendingPrimaryTagToDraft(defaultTagColorID: defaultTagColorID)
    }

    func updatePendingTag(tagID: UUID, number: String, colorID: UUID?, isPrimary: Bool, defaultTagColorID: UUID?) {
        pendingTags = AnimalTagDraftEditor.updateTag(
            in: pendingTags,
            tagID: tagID,
            number: number,
            colorID: resolvedColorID(number: number, colorID: colorID, defaultTagColorID: defaultTagColorID),
            isPrimary: isPrimary
        )
        syncPendingPrimaryTagToDraft(defaultTagColorID: defaultTagColorID)
    }

    private func syncPendingPrimaryTagToDraft(defaultTagColorID: UUID?) {
        if let primary = AnimalTagDraftEditor.primaryTag(in: pendingTags) {
            form.draft.tagNumber = primary.normalizedNumber
            form.draft.tagColorID = primary.normalizedNumber.isEmpty ? primary.colorID : (primary.colorID ?? defaultTagColorID)
        } else {
            form.draft.tagNumber = ""
            form.draft.tagColorID = nil
        }
    }

    private func resolvedColorID(number: String, colorID: UUID?, defaultTagColorID: UUID?) -> UUID? {
        number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? colorID : (colorID ?? defaultTagColorID)
    }
}
