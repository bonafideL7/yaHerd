import Foundation

@MainActor
struct CreateAnimalWithTagsUseCase {
    let repository: any AnimalCreating & AnimalTagAdding

    @discardableResult
    func execute(
        input: AnimalInput,
        tags desiredTags: [AnimalTagSnapshot],
        defaultTagColorID: UUID?
    ) throws -> AnimalDetailSnapshot {
        var created = try repository.create(input: input)

        for tag in desiredTags where tag.isActive && !tag.isPrimary && !tag.normalizedNumber.isEmpty {
            created = try repository.addTag(
                animalID: created.id,
                input: AnimalTagInput(
                    number: tag.normalizedNumber,
                    colorID: resolvedTagColorID(for: tag, defaultTagColorID: defaultTagColorID),
                    isPrimary: false
                )
            )
        }

        for tag in desiredTags where tag.isActive && tag.isPrimary && !tag.normalizedNumber.isEmpty {
            let represented = (created.activeTags + created.inactiveTags).contains { existing in
                existing.isActive
                    && existing.isPrimary
                    && existing.normalizedNumber == tag.normalizedNumber
                    && existing.colorID == resolvedTagColorID(for: tag, defaultTagColorID: defaultTagColorID)
            }

            if !represented {
                created = try repository.addTag(
                    animalID: created.id,
                    input: AnimalTagInput(
                        number: tag.normalizedNumber,
                        colorID: resolvedTagColorID(for: tag, defaultTagColorID: defaultTagColorID),
                        isPrimary: true
                    )
                )
            }
        }

        return created
    }

    private func resolvedTagColorID(for tag: AnimalTagSnapshot, defaultTagColorID: UUID?) -> UUID? {
        tag.normalizedNumber.isEmpty ? tag.colorID : (tag.colorID ?? defaultTagColorID)
    }
}
