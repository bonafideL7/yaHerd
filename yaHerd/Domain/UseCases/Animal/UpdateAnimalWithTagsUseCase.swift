import Foundation

struct UpdateAnimalWithTagsUseCase {
    let repository: any AnimalRepository

    @discardableResult
    func execute(
        animalID: UUID,
        input: AnimalInput,
        desiredTags: [AnimalTagSnapshot],
        defaultTagColorID: UUID?
    ) throws -> AnimalDetailSnapshot {
        try repository.updateWithTags(
            id: animalID,
            input: input,
            desiredTags: desiredTags,
            defaultTagColorID: defaultTagColorID
        )
    }
}
