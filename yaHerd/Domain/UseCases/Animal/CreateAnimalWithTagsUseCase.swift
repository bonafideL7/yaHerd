import Foundation

struct CreateAnimalWithTagsUseCase {
    let repository: any AnimalRepository

    @discardableResult
    func execute(
        input: AnimalInput,
        tags desiredTags: [AnimalTagSnapshot],
        defaultTagColorID: UUID?
    ) throws -> AnimalDetailSnapshot {
        try repository.createWithTags(
            input: input,
            desiredTags: desiredTags,
            defaultTagColorID: defaultTagColorID
        )
    }
}
