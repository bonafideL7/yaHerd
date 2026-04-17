import Foundation

struct OffspringDraftSeed: Hashable {
    let damID: UUID
    let damDisplayName: String
    let pastureID: UUID?
    let pastureName: String?
    let inferredSireID: UUID?
    let inferredSireDisplayName: String?

    func makeDraft() -> AnimalEditorDraft {
        AnimalEditorDraft(
            sex: .unknown,
            birthDate: .now,
            status: .active,
            pastureID: pastureID,
            sireID: inferredSireID,
            sire: inferredSireDisplayName ?? "",
            damID: damID,
            dam: damDisplayName
        )
    }
}
