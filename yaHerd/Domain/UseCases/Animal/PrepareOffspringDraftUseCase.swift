import Foundation

struct PrepareOffspringDraftUseCase {
    let repository: any AnimalOffspringDraftReading

    func execute(forDamID damID: UUID) throws -> PreparedAnimalEditor? {
        guard let seed = try repository.fetchOffspringDraftSeed(forDamID: damID) else {
            return nil
        }

        return PreparedAnimalEditor(
            draftSeed: seed,
            context: seed.makeEditorContext()
        )
    }
}
