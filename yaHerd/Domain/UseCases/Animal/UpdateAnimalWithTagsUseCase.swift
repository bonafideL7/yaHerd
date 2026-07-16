import Foundation

@MainActor
struct UpdateAnimalWithTagsUseCase {
    let repository: any AnimalUpdating & AnimalTagAdding & AnimalTagUpdating & AnimalTagRetiring

    @discardableResult
    func execute(
        animalID: UUID,
        input: AnimalInput,
        desiredTags: [AnimalTagSnapshot],
        defaultTagColorID: UUID?
    ) throws -> AnimalDetailSnapshot {
        var updated = try repository.update(id: animalID, input: input)
        var currentTagsByID = Dictionary(uniqueKeysWithValues: (updated.activeTags + updated.inactiveTags).map { ($0.id, $0) })

        let existingDesiredTags = desiredTags.filter { currentTagsByID[$0.id] != nil }
        let activeExistingNonPrimaryTags = existingDesiredTags.filter { $0.isActive && !$0.isPrimary }
        let inactiveExistingTags = existingDesiredTags.filter { !$0.isActive }
        let activeExistingPrimaryTags = existingDesiredTags.filter { $0.isActive && $0.isPrimary }

        for tag in activeExistingNonPrimaryTags {
            updated = try updateTag(animalID: animalID, tag: tag, isPrimary: false, defaultTagColorID: defaultTagColorID)
        }

        for tag in inactiveExistingTags {
            updated = try updateTag(animalID: animalID, tag: tag, isPrimary: false, defaultTagColorID: defaultTagColorID)
        }

        for tag in activeExistingPrimaryTags {
            updated = try updateTag(animalID: animalID, tag: tag, isPrimary: true, defaultTagColorID: defaultTagColorID)
        }

        currentTagsByID = Dictionary(uniqueKeysWithValues: (updated.activeTags + updated.inactiveTags).map { ($0.id, $0) })
        for tag in inactiveExistingTags where currentTagsByID[tag.id]?.isActive == true {
            updated = try repository.retireTag(animalID: animalID, tagID: tag.id)
        }

        currentTagsByID = Dictionary(uniqueKeysWithValues: (updated.activeTags + updated.inactiveTags).map { ($0.id, $0) })
        let newActiveTags = desiredTags.filter { currentTagsByID[$0.id] == nil && $0.isActive && !$0.normalizedNumber.isEmpty }

        for tag in newActiveTags where !tag.isPrimary {
            updated = try repository.addTag(
                animalID: animalID,
                input: makeTagInput(from: tag, isPrimary: false, defaultTagColorID: defaultTagColorID)
            )
        }

        for tag in newActiveTags where tag.isPrimary {
            let represented = (updated.activeTags + updated.inactiveTags).contains { existing in
                existing.isActive
                    && existing.isPrimary
                    && existing.normalizedNumber == tag.normalizedNumber
                    && existing.colorID == resolvedTagColorID(for: tag, defaultTagColorID: defaultTagColorID)
            }

            if !represented {
                updated = try repository.addTag(
                    animalID: animalID,
                    input: makeTagInput(from: tag, isPrimary: true, defaultTagColorID: defaultTagColorID)
                )
            }
        }

        return updated
    }

    private func updateTag(animalID: UUID, tag: AnimalTagSnapshot, isPrimary: Bool, defaultTagColorID: UUID?) throws -> AnimalDetailSnapshot {
        try repository.updateTag(
            animalID: animalID,
            tagID: tag.id,
            input: makeTagInput(from: tag, isPrimary: isPrimary, defaultTagColorID: defaultTagColorID)
        )
    }

    private func makeTagInput(from tag: AnimalTagSnapshot, isPrimary: Bool, defaultTagColorID: UUID?) -> AnimalTagInput {
        AnimalTagInput(
            number: tag.normalizedNumber,
            colorID: resolvedTagColorID(for: tag, defaultTagColorID: defaultTagColorID),
            isPrimary: isPrimary
        )
    }

    private func resolvedTagColorID(for tag: AnimalTagSnapshot, defaultTagColorID: UUID?) -> UUID? {
        tag.normalizedNumber.isEmpty ? tag.colorID : (tag.colorID ?? defaultTagColorID)
    }
}
