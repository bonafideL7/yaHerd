import Foundation

extension OffspringDraftSeed {
    func makeDraft() -> AnimalEditorDraft {
        AnimalEditorDraft(
            sex: .unknown,
            birthDate: defaultBirthDate,
            status: .active,
            pastureID: pastureID,
            sireID: inferredSireID,
            sire: inferredSireDisplayName ?? "",
            damID: damID,
            dam: damDisplayName
        )
    }
}

extension PreparedAnimalEditor {
    var draft: AnimalEditorDraft {
        draftSeed.makeDraft()
    }
}
