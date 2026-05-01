import Foundation

struct AnimalMapper {
    static func makeSummary(from animal: Animal) -> AnimalSummary {
        AnimalSummary(
            id: animal.publicID,
            name: animal.name,
            displayTagNumber: animal.displayTagNumber,
            displayTagColorID: animal.displayTagColorID,
            damDisplayTagNumber: AnimalDisplayTagFormatter.displayTagNumber(for: animal.damAnimal),
            damDisplayTagColorID: animal.damAnimal?.displayTagColorID,
            sex: animal.sex ?? .unknown,
            animalType: animal.animalType,
            firstDistinguishingFeature: animal.distinguishingFeatures.firstOrderedDistinguishingFeatureDescription,
            birthDate: animal.birthDate,
            status: animal.status,
            isArchived: animal.isArchived,
            pastureID: animal.pasture?.publicID,
            pastureName: animal.pasture?.name,
            location: animal.location
        )
    }

    static func makeDetail(from animal: Animal, statusReferenceName: String?) -> AnimalDetailSnapshot {
        AnimalDetailSnapshot(
            id: animal.publicID,
            name: animal.name,
            displayTagNumber: animal.displayTagNumber,
            displayTagColorID: animal.displayTagColorID,
            sex: animal.sex ?? .unknown,
            animalType: animal.animalType,
            birthDate: animal.birthDate,
            status: animal.status,
            pastureID: animal.pasture?.publicID,
            pastureName: animal.pasture?.name,
            sireID: animal.sireAnimal?.publicID,
            sire: animal.sireAnimal.map(parentDisplayName),
            damID: animal.damAnimal?.publicID,
            dam: animal.damAnimal.map(parentDisplayName),
            distinguishingFeatures: animal.distinguishingFeatures.normalizedDistinguishingFeatureOrder,
            saleDate: animal.saleDate,
            salePrice: animal.salePrice,
            reasonSold: animal.reasonSold,
            deathDate: animal.deathDate,
            causeOfDeath: animal.causeOfDeath,
            statusReferenceID: animal.statusReferenceID,
            statusReferenceName: statusReferenceName,
            isArchived: animal.isArchived,
            archivedAt: animal.archivedAt,
            archiveReason: animal.archiveReason,
            activeTags: animal.activeTags.map(makeTagSnapshot),
            inactiveTags: animal.inactiveTags.map(makeTagSnapshot),
            location: animal.location,
            maternalOffspring: animal.maternalOffspring
                .filter { !$0.isSoftDeleted }
                .sorted { lhs, rhs in
                    if lhs.birthDate != rhs.birthDate { return lhs.birthDate > rhs.birthDate }
                    return lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
                }
                .map(makeSummary)
        )
    }

    static func makeParentOption(from animal: Animal) -> AnimalParentOption {
        AnimalParentOption(
            id: animal.publicID,
            name: animal.name,
            displayTagNumber: animal.displayTagNumber,
            displayTagColorID: animal.displayTagColorID,
            sex: animal.sex ?? .unknown,
            isArchived: animal.isArchived
        )
    }

    static func makeTagSnapshot(from tag: AnimalTag) -> AnimalTagSnapshot {
        AnimalTagSnapshot(
            id: tag.publicID,
            number: tag.number,
            colorID: tag.colorID,
            isPrimary: tag.isPrimary,
            isActive: tag.isActive,
            assignedAt: tag.assignedAt,
            removedAt: tag.removedAt
        )
    }

    static func makeTimeline(from animal: Animal) -> [AnimalTimelineEvent] {
        animal.timelineEvents
    }

    private static func parentDisplayName(for animal: Animal) -> String {
        let trimmedTag = animal.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTag.isEmpty { return trimmedTag }

        let trimmedName = animal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }

        switch animal.sex ?? .unknown {
        case .female:
            return "Untagged dam"
        case .male:
            return "Untagged sire"
        case .unknown:
            return "Untagged animal"
        }
    }

}
