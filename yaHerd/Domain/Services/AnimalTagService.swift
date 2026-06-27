import Foundation

struct AnimalTagState: Hashable, Identifiable {
    let id: UUID
    let number: String
    let colorID: UUID?
    let isPrimary: Bool
    let isActive: Bool
    let assignedAt: Date
    let removedAt: Date?

    var normalizedNumber: String {
        number.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AnimalPrimaryTagFields: Hashable {
    let number: String
    let colorID: UUID?
}

enum AnimalTagService {
    static func activeTags(_ tags: [AnimalTagState]) -> [AnimalTagState] {
        tags
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary && !rhs.isPrimary }
                if lhs.assignedAt != rhs.assignedAt { return lhs.assignedAt > rhs.assignedAt }
                return lhs.number.localizedStandardCompare(rhs.number) == .orderedAscending
            }
    }

    static func inactiveTags(_ tags: [AnimalTagState]) -> [AnimalTagState] {
        tags
            .filter { !$0.isActive }
            .sorted { lhs, rhs in
                let leftDate = lhs.removedAt ?? lhs.assignedAt
                let rightDate = rhs.removedAt ?? rhs.assignedAt
                return leftDate > rightDate
            }
    }

    static func primaryTag(in tags: [AnimalTagState]) -> AnimalTagState? {
        let active = activeTags(tags)
        return active.first(where: \.isPrimary) ?? active.first
    }

    static func secondaryActiveTags(in tags: [AnimalTagState]) -> [AnimalTagState] {
        let active = activeTags(tags)
        guard let primary = primaryTag(in: tags) else { return active }
        return active.filter { $0.id != primary.id }
    }

    static func primaryTagFields(
        in tags: [AnimalTagState],
        fallbackNumber: String,
        fallbackColorID: UUID?
    ) -> AnimalPrimaryTagFields {
        guard let primary = primaryTag(in: tags) else {
            return AnimalPrimaryTagFields(number: fallbackNumber, colorID: fallbackColorID)
        }

        return AnimalPrimaryTagFields(number: primary.normalizedNumber, colorID: primary.colorID)
    }

    static func shouldMakeAddedTagPrimary(isPrimary: Bool, existingTags: [AnimalTagState]) -> Bool {
        isPrimary || activeTags(existingTags).isEmpty
    }

    static func replacementPrimaryTagID(afterRetiring retiredTagID: UUID, from tags: [AnimalTagState]) -> UUID? {
        activeTags(tags.filter { $0.id != retiredTagID }).first?.id
    }
}
