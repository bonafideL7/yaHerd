import Foundation

enum AnimalTagDraftEditor {
    static func addTag(
        to tags: [AnimalTagSnapshot],
        number: String,
        colorID: UUID?,
        isPrimary: Bool,
        assignedAt: Date = .now
    ) -> [AnimalTagSnapshot] {
        let normalizedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNumber.isEmpty else { return tags }

        let shouldBePrimary = isPrimary || tags.filter(\.isActive).isEmpty
        let adjustedTags = shouldBePrimary ? clearPrimary(in: tags) : tags

        return adjustedTags + [
            AnimalTagSnapshot(
                id: UUID(),
                number: normalizedNumber,
                colorID: colorID,
                isPrimary: shouldBePrimary,
                isActive: true,
                assignedAt: assignedAt,
                removedAt: nil
            )
        ]
    }

    static func updateTag(
        in tags: [AnimalTagSnapshot],
        tagID: UUID,
        number: String,
        colorID: UUID?,
        isPrimary: Bool
    ) -> [AnimalTagSnapshot] {
        let normalizedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNumber.isEmpty else { return tags }

        let hasOtherActiveTags = tags.contains { $0.id != tagID && $0.isActive }
        let shouldBePrimary = isPrimary || !hasOtherActiveTags

        return tags.map { tag in
            AnimalTagSnapshot(
                id: tag.id,
                number: tag.id == tagID ? normalizedNumber : tag.number,
                colorID: tag.id == tagID ? colorID : tag.colorID,
                isPrimary: tag.id == tagID
                    ? (tag.isActive ? shouldBePrimary : false)
                    : ((shouldBePrimary && tag.isActive) ? false : tag.isPrimary),
                isActive: tag.isActive,
                assignedAt: tag.assignedAt,
                removedAt: tag.removedAt
            )
        }
    }

    static func promoteTag(in tags: [AnimalTagSnapshot], tagID: UUID) -> [AnimalTagSnapshot] {
        tags.map { tag in
            AnimalTagSnapshot(
                id: tag.id,
                number: tag.number,
                colorID: tag.colorID,
                isPrimary: tag.id == tagID && tag.isActive,
                isActive: tag.isActive,
                assignedAt: tag.assignedAt,
                removedAt: tag.removedAt
            )
        }
    }

    static func retireTag(
        in tags: [AnimalTagSnapshot],
        tagID: UUID,
        persistedTagIDs: Set<UUID>,
        removedAt: Date = .now
    ) -> [AnimalTagSnapshot] {
        let retiredTags: [AnimalTagSnapshot]

        if persistedTagIDs.contains(tagID) {
            retiredTags = tags.map { tag in
                guard tag.id == tagID else { return tag }
                return AnimalTagSnapshot(
                    id: tag.id,
                    number: tag.number,
                    colorID: tag.colorID,
                    isPrimary: false,
                    isActive: false,
                    assignedAt: tag.assignedAt,
                    removedAt: tag.removedAt ?? removedAt
                )
            }
        } else {
            retiredTags = tags.filter { $0.id != tagID }
        }

        guard !retiredTags.contains(where: { $0.isActive && $0.isPrimary }) else {
            return retiredTags
        }

        guard let firstActiveID = retiredTags.first(where: { $0.isActive })?.id else {
            return retiredTags
        }

        return promoteTag(in: retiredTags, tagID: firstActiveID)
    }

    static func primaryTag(in tags: [AnimalTagSnapshot]) -> AnimalTagSnapshot? {
        tags.first { $0.isActive && $0.isPrimary }
    }

    private static func clearPrimary(in tags: [AnimalTagSnapshot]) -> [AnimalTagSnapshot] {
        tags.map { tag in
            AnimalTagSnapshot(
                id: tag.id,
                number: tag.number,
                colorID: tag.colorID,
                isPrimary: false,
                isActive: tag.isActive,
                assignedAt: tag.assignedAt,
                removedAt: tag.removedAt
            )
        }
    }
}
