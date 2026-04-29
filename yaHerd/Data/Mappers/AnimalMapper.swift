import Foundation

struct AnimalMapper {
    static func makeSummary(from animal: Animal) -> AnimalSummary {
        AnimalSummary(
            id: animal.publicID,
            name: animal.name,
            displayTagNumber: animal.displayTagNumber,
            displayTagColorID: animal.displayTagColorID,
            damDisplayTagNumber: animal.damAnimal?.displayTagNumber,
            damDisplayTagColorID: animal.damAnimal?.displayTagColorID,
            sex: animal.sex ?? .unknown,
            animalType: animal.animalType,
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
            sire: animal.sireAnimal?.displayTagNumber,
            damID: animal.damAnimal?.publicID,
            dam: animal.damAnimal?.displayTagNumber,
            distinguishingFeatures: animal.distinguishingFeatures,
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

}
