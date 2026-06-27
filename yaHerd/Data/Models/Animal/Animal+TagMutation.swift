import Foundation

extension Animal {
    var activeTags: [AnimalTag] {
        tags.sortedLikeTagStateResult(AnimalTagService.activeTags(tags.map(\.domainState)))
    }

    var inactiveTags: [AnimalTag] {
        tags.sortedLikeTagStateResult(AnimalTagService.inactiveTags(tags.map(\.domainState)))
    }

    var primaryTag: AnimalTag? {
        guard let primaryID = AnimalTagService.primaryTag(in: tags.map(\.domainState))?.id else {
            return nil
        }
        return tags.first { $0.publicID == primaryID }
    }

    var secondaryActiveTags: [AnimalTag] {
        tags.sortedLikeTagStateResult(AnimalTagService.secondaryActiveTags(in: tags.map(\.domainState)))
    }

    var displayTagNumber: String {
        AnimalTagService.primaryTagFields(
            in: tags.map(\.domainState),
            fallbackNumber: tagNumber,
            fallbackColorID: tagColorID
        ).number
    }

    var displayTagColorID: UUID? {
        AnimalTagService.primaryTagFields(
            in: tags.map(\.domainState),
            fallbackNumber: tagNumber,
            fallbackColorID: tagColorID
        ).colorID
    }

    func syncPrimaryTagFieldsFromTags() {
        let fields = AnimalTagService.primaryTagFields(
            in: tags.map(\.domainState),
            fallbackNumber: "",
            fallbackColorID: nil
        )
        tagNumber = fields.number
        tagColorID = fields.colorID
    }

    func ensurePrimaryTagRecord() -> AnimalTag {
        if let primaryTag {
            if primaryTag.normalizedNumber != tagNumber {
                primaryTag.number = tagNumber
            }
            if primaryTag.colorID != tagColorID {
                primaryTag.colorID = tagColorID
            }
            if !primaryTag.isActive {
                primaryTag.isActive = true
                primaryTag.removedAt = nil
            }
            primaryTag.isPrimary = true
            return primaryTag
        }

        let tag = AnimalTag(
            number: tagNumber,
            colorID: tagColorID,
            isPrimary: true,
            isActive: true,
            assignedAt: .now,
            animal: self
        )
        tags.append(tag)
        syncPrimaryTagFieldsFromTags()
        return tag
    }

    func addTag(number: String, colorID: UUID?, isPrimary: Bool, assignedAt: Date = .now) -> AnimalTag {
        let trimmedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldBePrimary = AnimalTagService.shouldMakeAddedTagPrimary(
            isPrimary: isPrimary,
            existingTags: tags.map(\.domainState)
        )

        if shouldBePrimary {
            for tag in tags where tag.isActive {
                tag.isPrimary = false
            }
        }

        let tag = AnimalTag(
            number: trimmedNumber,
            colorID: colorID,
            isPrimary: shouldBePrimary,
            isActive: true,
            assignedAt: assignedAt,
            animal: self
        )
        tags.append(tag)
        syncPrimaryTagFieldsFromTags()
        return tag
    }

    func updatePrimaryTag(number: String, colorID: UUID?) {
        let trimmedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        tagNumber = trimmedNumber
        tagColorID = colorID

        let tag = ensurePrimaryTagRecord()
        tag.number = trimmedNumber
        tag.colorID = colorID

        for otherTag in tags where otherTag.publicID != tag.publicID && otherTag.isActive {
            otherTag.isPrimary = false
        }

        syncPrimaryTagFieldsFromTags()
    }

    func updateTag(_ tag: AnimalTag, number: String, colorID: UUID?, isPrimary: Bool) {
        let trimmedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        tag.number = trimmedNumber
        tag.colorID = colorID

        if tag.isActive {
            if isPrimary {
                for existingTag in tags where existingTag.isActive {
                    existingTag.isPrimary = existingTag.publicID == tag.publicID
                }
            } else if activeTags.filter({ $0.publicID != tag.publicID }).isEmpty {
                tag.isPrimary = true
            } else {
                tag.isPrimary = false
                if primaryTag == nil, let firstActiveTag = activeTags.first {
                    firstActiveTag.isPrimary = true
                }
            }
        } else {
            tag.isPrimary = false
        }

        syncPrimaryTagFieldsFromTags()
    }

    func promoteTagToPrimary(_ tag: AnimalTag) {
        for existingTag in tags where existingTag.isActive {
            existingTag.isPrimary = existingTag.publicID == tag.publicID
        }
        tag.isActive = true
        tag.removedAt = nil
        syncPrimaryTagFieldsFromTags()
    }

    func retireTag(_ tag: AnimalTag, on date: Date = .now) {
        let replacementID = AnimalTagService.replacementPrimaryTagID(
            afterRetiring: tag.publicID,
            from: tags.map(\.domainState)
        )

        tag.isActive = false
        tag.isPrimary = false
        tag.removedAt = date

        if let replacement = tags.first(where: { $0.publicID == replacementID }) {
            replacement.isPrimary = true
            replacement.isActive = true
            replacement.removedAt = nil
        }

        syncPrimaryTagFieldsFromTags()
    }
}

private extension AnimalTag {
    var domainState: AnimalTagState {
        AnimalTagState(
            id: publicID,
            number: number,
            colorID: colorID,
            isPrimary: isPrimary,
            isActive: isActive,
            assignedAt: assignedAt,
            removedAt: removedAt
        )
    }
}

private extension Array where Element == AnimalTag {
    func sortedLikeTagStateResult(_ orderedStates: [AnimalTagState]) -> [AnimalTag] {
        let tagsByID = Dictionary(uniqueKeysWithValues: map { ($0.publicID, $0) })
        return orderedStates.compactMap { tagsByID[$0.id] }
    }
}
