import Foundation

struct OffspringDraftSeed: Hashable {
    let damID: UUID
    let damDisplayName: String
    let pastureID: UUID?
    let pastureName: String?
    let inferredSireID: UUID?
    let inferredSireDisplayName: String?
    let defaultBirthDate: Date

    func makeEditorContext() -> AnimalEditorContext {
        AnimalEditorContext(
            kind: .offspring(
                .init(
                    damDisplayName: damDisplayName,
                    pastureName: pastureName,
                    inferredSireDisplayName: inferredSireDisplayName
                )
            )
        )
    }
}
