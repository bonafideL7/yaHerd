@preconcurrency import CoreData
import Foundation

enum CoreDataAnimalProjection {
    static func summary(_ animal: CDAnimal) -> AnimalSummary {
        let tags = managedTags(animal)
        let primary = primaryTagFields(tags)
        let damPrimary = animal.dam.map { primaryTagFields(managedTags($0)) }

        let pregnancyChecks = managedPregnancyChecks(animal)
        let latestPregnancyCheck = pregnancyChecks.max { $0.date < $1.date }
        let latestPregnancyResult = latestPregnancyCheck.flatMap {
            PregnancyResult(rawValue: $0.resultRawValue)
        }
        let expectedCalvingDate: Date? = {
            guard latestPregnancyResult == .pregnant, let latestPregnancyCheck else {
                return nil
            }
            if let dueDate = latestPregnancyCheck.dueDate {
                return dueDate
            }
            return Calendar.current.date(
                byAdding: .day,
                value: CattleReproductionRules.gestationDays,
                to: latestPregnancyCheck.date
            )
        }()

        let healthRecords = managedHealthRecords(animal)
        let sex = Sex(rawValue: animal.sexRawValue) ?? .unknown

        return AnimalSummary(
            id: animal.id,
            name: animal.name,
            displayTagNumber: primary.number,
            displayTagColorID: primary.colorID,
            damDisplayTagNumber: animal.dam == nil
                ? nil
                : (damPrimary?.number.isEmpty == false ? damPrimary?.number : AnimalDisplayTagFormatter.untaggedPlaceholder),
            damDisplayTagColorID: damPrimary?.colorID,
            sex: sex,
            animalType: animalType(animal),
            firstDistinguishingFeature: distinguishingFeatures(animal)
                .firstOrderedDistinguishingFeatureDescription,
            birthDate: animal.birthDate,
            status: AnimalStatus(rawValue: animal.statusRawValue) ?? .active,
            isArchived: animal.isArchived,
            pastureID: animal.currentPasture?.id,
            pastureName: animal.currentPasture?.name,
            location: animal.activeWorkingSession == nil ? .pasture : .workingPen,
            lastPregnancyCheckDate: latestPregnancyCheck?.date,
            lastPregnancyStatus: pregnancyStatus(latestPregnancyResult),
            expectedCalvingDate: expectedCalvingDate,
            lastTreatmentDate: healthRecords.map(\.date).max()
        )
    }

    static func detail(_ animal: CDAnimal) -> AnimalDetailSnapshot {
        let activeTags = orderedTags(
            managedTags(animal),
            matching: AnimalTagService.activeTags
        )
        let inactiveTags = orderedTags(
            managedTags(animal),
            matching: AnimalTagService.inactiveTags
        )
        let primary = primaryTagFields(managedTags(animal))
        let visibleMaternalOffspring = managedMaternalOffspring(animal)
            .filter { !$0.isArchived }
            .sorted {
                if $0.birthDate != $1.birthDate {
                    return $0.birthDate > $1.birthDate
                }
                return primaryTagFields(managedTags($0)).number.localizedStandardCompare(
                    primaryTagFields(managedTags($1)).number
                ) == .orderedAscending
            }

        return AnimalDetailSnapshot(
            id: animal.id,
            name: animal.name,
            displayTagNumber: primary.number,
            displayTagColorID: primary.colorID,
            sex: Sex(rawValue: animal.sexRawValue) ?? .unknown,
            animalType: animalType(animal),
            birthDate: animal.birthDate,
            status: AnimalStatus(rawValue: animal.statusRawValue) ?? .active,
            pastureID: animal.currentPasture?.id,
            pastureName: animal.currentPasture?.name,
            sireID: animal.sire?.id,
            sire: animal.sire.map(parentDisplayName),
            damID: animal.dam?.id,
            dam: animal.dam.map(parentDisplayName),
            distinguishingFeatures: distinguishingFeatures(animal)
                .normalizedDistinguishingFeatureOrder,
            saleDate: animal.saleDate,
            salePrice: animal.salePrice?.doubleValue,
            reasonSold: animal.reasonSold,
            deathDate: animal.deathDate,
            causeOfDeath: animal.causeOfDeath,
            statusReferenceID: animal.statusReference?.id,
            statusReferenceName: animal.statusReference?.name,
            isArchived: animal.isArchived,
            archivedAt: animal.archivedAt,
            archiveReason: animal.archiveReason,
            activeTags: activeTags.map(tagSnapshot),
            inactiveTags: inactiveTags.map(tagSnapshot),
            location: animal.activeWorkingSession == nil ? .pasture : .workingPen,
            maternalOffspringCountIncludingArchived: managedMaternalOffspring(animal).count,
            maternalOffspring: visibleMaternalOffspring.map(summary)
        )
    }

    static func parentOption(_ animal: CDAnimal) -> AnimalParentOption {
        let primary = primaryTagFields(managedTags(animal))
        return AnimalParentOption(
            id: animal.id,
            name: animal.name,
            displayTagNumber: primary.number,
            displayTagColorID: primary.colorID,
            sex: Sex(rawValue: animal.sexRawValue) ?? .unknown,
            isArchived: animal.isArchived
        )
    }

    static func tagSnapshot(_ tag: CDAnimalTag) -> AnimalTagSnapshot {
        AnimalTagSnapshot(
            id: tag.id,
            number: tag.number,
            colorID: tag.color?.id,
            isPrimary: tag.isPrimary,
            isActive: tag.isActive,
            assignedAt: tag.assignedAt,
            removedAt: tag.removedAt
        )
    }

    static func timeline(_ animal: CDAnimal) -> [AnimalTimelineEvent] {
        var events: [AnimalTimelineEvent] = [
            AnimalTimelineEvent(
                date: animal.birthDate,
                type: .birth,
                title: "Birth",
                details: birthEventDetails(animal)
            )
        ]

        for offspring in managedMaternalOffspring(animal) where !offspring.isArchived {
            events.append(
                AnimalTimelineEvent(
                    date: offspring.birthDate,
                    type: .birth,
                    title: "Offspring Recorded",
                    details: offspringBirthEventDetails(offspring)
                )
            )
        }

        for record in managedHealthRecords(animal) {
            events.append(
                AnimalTimelineEvent(
                    date: record.date,
                    type: .health,
                    title: record.treatment,
                    details: record.notes
                )
            )
        }

        for check in managedPregnancyChecks(animal) {
            let result = PregnancyResult(rawValue: check.resultRawValue) ?? .unknown
            events.append(
                AnimalTimelineEvent(
                    date: check.date,
                    type: .pregnancy,
                    title: "Pregnancy Check: \(result.rawValue.capitalized)",
                    details: check.technician
                )
            )
        }

        for movement in managedMovementRecords(animal) {
            events.append(
                AnimalTimelineEvent(
                    date: movement.date,
                    type: .movement,
                    title: "Pasture Movement",
                    details: "\(movement.fromPastureNameSnapshot ?? "—") → \(movement.toPastureNameSnapshot ?? "—")"
                )
            )
        }

        for record in managedStatusRecords(animal) {
            let oldStatus = AnimalStatus(rawValue: record.oldStatusRawValue) ?? .active
            let newStatus = AnimalStatus(rawValue: record.newStatusRawValue) ?? .active
            events.append(
                AnimalTimelineEvent(
                    date: record.date,
                    type: .status,
                    title: "Status Change",
                    details: "\(oldStatus.label) → \(newStatus.label)"
                )
            )
        }

        for tag in managedTags(animal) {
            let normalizedNumber = tag.number.trimmingCharacters(in: .whitespacesAndNewlines)
            events.append(
                AnimalTimelineEvent(
                    date: tag.assignedAt,
                    type: .tag,
                    title: "Tag Assigned",
                    details: normalizedNumber
                )
            )
            if let removedAt = tag.removedAt {
                events.append(
                    AnimalTimelineEvent(
                        date: removedAt,
                        type: .tag,
                        title: "Tag Retired",
                        details: normalizedNumber
                    )
                )
            }
        }

        return events.sorted {
            if $0.date != $1.date {
                return $0.date > $1.date
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    static func primaryTagFields(_ tags: [CDAnimalTag]) -> AnimalPrimaryTagFields {
        AnimalTagService.primaryTagFields(
            in: tags.map(tagState),
            fallbackNumber: "",
            fallbackColorID: nil
        )
    }

    static func tagState(_ tag: CDAnimalTag) -> AnimalTagState {
        AnimalTagState(
            id: tag.id,
            number: tag.number,
            colorID: tag.color?.id,
            isPrimary: tag.isPrimary,
            isActive: tag.isActive,
            assignedAt: tag.assignedAt,
            removedAt: tag.removedAt
        )
    }

    static func managedTags(_ animal: CDAnimal) -> [CDAnimalTag] {
        (animal.tags?.allObjects as? [CDAnimalTag]) ?? []
    }

    static func managedHealthRecords(_ animal: CDAnimal) -> [CDHealthRecord] {
        (animal.healthRecords?.allObjects as? [CDHealthRecord]) ?? []
    }

    static func managedPregnancyChecks(_ animal: CDAnimal) -> [CDPregnancyCheck] {
        (animal.pregnancyChecks?.allObjects as? [CDPregnancyCheck]) ?? []
    }

    static func managedMovementRecords(_ animal: CDAnimal) -> [CDMovementRecord] {
        (animal.movementRecords?.allObjects as? [CDMovementRecord]) ?? []
    }

    static func managedStatusRecords(_ animal: CDAnimal) -> [CDStatusRecord] {
        (animal.statusRecords?.allObjects as? [CDStatusRecord]) ?? []
    }

    static func managedMaternalOffspring(_ animal: CDAnimal) -> [CDAnimal] {
        (animal.damOffspring?.allObjects as? [CDAnimal]) ?? []
    }

    static func distinguishingFeatures(_ animal: CDAnimal) -> [DistinguishingFeature] {
        (try? JSONDecoder().decode(
            [DistinguishingFeature].self,
            from: animal.distinguishingFeaturesData
        )) ?? []
    }

    static func animalType(_ animal: CDAnimal) -> AnimalType {
        AnimalTypeClassifier.classify(
            sex: Sex(rawValue: animal.sexRawValue) ?? .unknown,
            birthDate: animal.birthDate,
            hasMaternalOffspring: !managedMaternalOffspring(animal).isEmpty,
            hasCastrationOrBandingRecord: managedHealthRecords(animal).contains {
                AnimalTypeClassifier.isCastrationOrBandingTreatment($0.treatment)
            }
        )
    }

    static func parentDisplayName(_ animal: CDAnimal) -> String {
        let tag = primaryTagFields(managedTags(animal)).number
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty {
            return tag
        }

        let name = animal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }

        switch Sex(rawValue: animal.sexRawValue) ?? .unknown {
        case .female:
            return "Untagged dam"
        case .male:
            return "Untagged sire"
        case .unknown:
            return "Untagged animal"
        }
    }

    private static func orderedTags(
        _ tags: [CDAnimalTag],
        matching ordering: ([AnimalTagState]) -> [AnimalTagState]
    ) -> [CDAnimalTag] {
        let orderedIDs = ordering(tags.map(tagState)).map(\.id)
        return orderedIDs.compactMap { id in
            tags.first { $0.id == id }
        }
    }

    private static func pregnancyStatus(_ result: PregnancyResult?) -> AnimalPregnancyStatus? {
        guard let result else {
            return nil
        }
        switch result {
        case .open:
            return .open
        case .pregnant:
            return .pregnant
        case .unknown:
            return .unknown
        }
    }

    private static func birthEventDetails(_ animal: CDAnimal) -> String? {
        var details: [String] = []
        if let dam = animal.dam {
            let display = primaryTagFields(managedTags(dam)).number
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                details.append("Dam: \(display)")
            }
        }
        if let sire = animal.sire {
            let display = primaryTagFields(managedTags(sire)).number
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                details.append("Sire: \(display)")
            }
        }
        if let pastureName = animal.currentPasture?.name, !pastureName.isEmpty {
            details.append("Pasture: \(pastureName)")
        }
        return details.isEmpty ? nil : details.joined(separator: " • ")
    }

    private static func offspringBirthEventDetails(_ offspring: CDAnimal) -> String {
        var components = [
            "Offspring: \(primaryTagFields(managedTags(offspring)).number)"
        ]
        let name = offspring.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            components.append("Name: \(offspring.name)")
        }
        if let sire = offspring.sire {
            let display = primaryTagFields(managedTags(sire)).number
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                components.append("Sire: \(display)")
            }
        }
        return components.joined(separator: " • ")
    }
}
