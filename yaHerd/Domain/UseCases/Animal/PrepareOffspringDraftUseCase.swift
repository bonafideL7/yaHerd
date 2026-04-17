import Foundation

struct PrepareOffspringDraftUseCase {
    let repository: any AnimalRepository

    func execute(forDamID damID: UUID) throws -> OffspringDraftSeed? {
        try repository.fetchOffspringDraftSeed(forDamID: damID)
    }
}
