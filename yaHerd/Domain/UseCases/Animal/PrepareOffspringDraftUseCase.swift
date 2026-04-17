import Foundation

struct PrepareOffspringDraftUseCase {
    let repository: any AnimalRepository

    func execute(forDamID damID: UUID) throws -> PreparedAnimalEditor? {
        guard let seed = try repository.fetchOffspringDraftSeed(forDamID: damID) else {
            return nil
        }

        return PreparedAnimalEditor(
            draft: seed.makeDraft(),
            context: seed.makeEditorContext()
        )
    }
}
