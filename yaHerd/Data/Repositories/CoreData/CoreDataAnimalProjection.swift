@preconcurrency import CoreData
import Foundation

enum CoreDataAnimalPayloadCodec {
    static func encodeDistinguishingFeatures(
        _ features: [DistinguishingFeature]
    ) throws -> Data {
        try JSONEncoder().encode(features.normalizedDistinguishingFeatureOrder)
    }

    static func decodeDistinguishingFeatures(
        _ data: Data,
        animalID: UUID
    ) throws -> [DistinguishingFeature] {
        do {
            return try JSONDecoder().decode([DistinguishingFeature].self, from: data)
        } catch {
            throw CoreDataAnimalRepositoryError.corruptDistinguishingFeatures(
                animalID: animalID
            )
        }
    }
}

enum CoreDataAnimalProjection {
    private struct TimelineProjectionEvent {
        let event: AnimalTimelineEvent
        let sourceID: UUID
        let kindOrder: Int
    }

    static func summary(
        _ animal: CDAnimal,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> AnimalSummary {
        try CoreDataAnimalMutation.validateOwnedGraphIdentity(animal)
        let tags = managedTags(animal)
        let primary = primaryTagFields(tags)
        let damPrimary = animal.dam.map { primaryTagFields(managedTags($0)) }

        let pregnancyChecks = managedPregnancyChecks(animal)
        let latestPregnancyCheck = pregnancyChecks.max { $0.date < $1.date }
        let latestPregnancyResult = try latestPregnancyCheck.map {
            try pregnancyResult($0)
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
        let sex = try sex(animal)

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
            animalType: try animalType(
                animal,
                now: now,
                calendar: calendar
            ),
            firstDistinguishingFeature: try distinguishingFeatures(animal)
                .firstOrderedDistinguishingFeatureDescription,
            birthDate: animal.birthDate,
            status: try status(animal),
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

    static func detail(_ animal: CDAnimal) throws -> AnimalDetailSnapshot {
        try CoreDataAnimalMutation.validateOwnedGraphIdentity(animal)
        let activeTags = orderedTags(
            managedTags(animal),
            matching: AnimalTagService.activeTags
        )
        let inactiveTags = orderedTags(
            managedTags(animal),
            matching: AnimalTagService.inactiveTags
        )
        let primary = primaryTagFields(managedTags(animal))
        let maternalOffspring = managedMaternalOffspring(animal)
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
            sex: try sex(animal),
            animalType: try animalType(animal),
            birthDate: animal.birthDate,
            status: try status(animal),
            pastureID: animal.currentPasture?.id,
            pastureName: animal.currentPasture?.name,
            sireID: animal.sire?.id,
            sire: try animal.sire.map { try parentDisplayName($0) },
            damID: animal.dam?.id,
            dam: try animal.dam.map { try parentDisplayName($0) },
            distinguishingFeatures: try distinguishingFeatures(animal)
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
            maternalOffspring: try maternalOffspring.map { offspring in
                try summary(offspring)
            }
        )
    }

    static func parentOption(_ animal: CDAnimal) throws -> AnimalParentOption {
        try CoreDataAnimalMutation.validateOwnedGraphIdentity(animal)
        let primary = primaryTagFields(managedTags(animal))
        return AnimalParentOption(
            id: animal.id,
            name: animal.name,
            displayTagNumber: primary.number,
            displayTagColorID: primary.colorID,
            sex: try sex(animal),
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

    static func timeline(_ animal: CDAnimal) throws -> [AnimalTimelineEvent] {
        try CoreDataAnimalMutation.validateOwnedGraphIdentity(animal)
        var events: [TimelineProjectionEvent] = [
            TimelineProjectionEvent(
                event: AnimalTimelineEvent(
                    date: animal.birthDate,
                    type: .birth,
                    title: "Birth",
                    details: birthEventDetails(animal)
                ),
                sourceID: animal.id,
                kindOrder: 0
            )
        ]

        for offspring in managedMaternalOffspring(animal) where !offspring.isArchived {
            events.append(
                TimelineProjectionEvent(
                    event: AnimalTimelineEvent(
                        date: offspring.birthDate,
                        type: .birth,
                        title: "Offspring Recorded",
                        details: offspringBirthEventDetails(offspring)
                    ),
                    sourceID: offspring.id,
                    kindOrder: 1
                )
            )
        }

        for record in managedHealthRecords(animal) {
            events.append(
                TimelineProjectionEvent(
                    event: AnimalTimelineEvent(
                        date: record.date,
                        type: .health,
                        title: record.treatment,
                        details: record.notes
                    ),
                    sourceID: record.id,
                    kindOrder: 0
                )
            )
        }

        for check in managedPregnancyChecks(animal) {
            let result = try pregnancyResult(check)
            events.append(
                TimelineProjectionEvent(
                    event: AnimalTimelineEvent(
                        date: check.date,
                        type: .pregnancy,
                        title: "Pregnancy Check: \(result.rawValue.capitalized)",
                        details: check.technician
                    ),
                    sourceID: check.id,
                    kindOrder: 0
                )
            )
        }

        for movement in managedMovementRecords(animal) {
            events.append(
                TimelineProjectionEvent(
                    event: AnimalTimelineEvent(
                        date: movement.date,
                        type: .movement,
                        title: "Pasture Movement",
                        details: "\(movement.fromPastureNameSnapshot ?? "—") → \(movement.toPastureNameSnapshot ?? "—")"
                    ),
                    sourceID: movement.id,
                    kindOrder: 0
                )
            )
        }

        for record in managedStatusRecords(animal) {
            let oldStatus = try statusHistoryValue(record.oldStatusRawValue, record: record)
            let newStatus = try statusHistoryValue(record.newStatusRawValue, record: record)
            events.append(
                TimelineProjectionEvent(
                    event: AnimalTimelineEvent(
                        date: record.date,
                        type: .status,
                        title: "Status Change",
                        details: "\(oldStatus.label) → \(newStatus.label)"
                    ),
                    sourceID: record.id,
                    kindOrder: 0
                )
            )
        }

        for tag in managedTags(animal) {
            let normalizedNumber = tag.number.trimmingCharacters(in: .whitespacesAndNewlines)
            events.append(
                TimelineProjectionEvent(
                    event: AnimalTimelineEvent(
                        date: tag.assignedAt,
                        type: .tag,
                        title: "Tag Assigned",
                        details: normalizedNumber
                    ),
                    sourceID: tag.id,
                    kindOrder: 0
                )
            )
            if let removedAt = tag.removedAt {
                events.append(
                    TimelineProjectionEvent(
                        event: AnimalTimelineEvent(
                            date: removedAt,
                            type: .tag,
                            title: "Tag Retired",
                            details: normalizedNumber
                        ),
                        sourceID: tag.id,
                        kindOrder: 1
                    )
                )
            }
        }

        return events.sorted(by: timelineSort).map(\.event)
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

    static func distinguishingFeatures(_ animal: CDAnimal) throws -> [DistinguishingFeature] {
        try CoreDataAnimalPayloadCodec.decodeDistinguishingFeatures(
            animal.distinguishingFeaturesData,
            animalID: animal.id
        )
    }

    static func animalType(
        _ animal: CDAnimal,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> AnimalType {
        AnimalTypeClassifier.classify(
            sex: try sex(animal),
            birthDate: animal.birthDate,
            hasMaternalOffspring: !managedMaternalOffspring(animal).isEmpty,
            hasCastrationOrBandingRecord: managedHealthRecords(animal).contains {
                AnimalTypeClassifier.isCastrationOrBandingTreatment($0.treatment)
            },
            now: now,
            calendar: calendar
        )
    }

    static func parentDisplayName(_ animal: CDAnimal) throws -> String {
        let tag = primaryTagFields(managedTags(animal)).number
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty {
            return tag
        }

        let name = animal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }

        switch try sex(animal) {
        case .female:
            return "Untagged dam"
        case .male:
            return "Untagged sire"
        case .unknown:
            return "Untagged animal"
        }
    }

    static func sex(_ animal: CDAnimal) throws -> Sex {
        guard let value = Sex(rawValue: animal.sexRawValue) else {
            throw CoreDataAnimalRepositoryError.invalidAnimalSexRawValue(
                animalID: animal.id,
                value: animal.sexRawValue
            )
        }
        return value
    }

    static func status(_ animal: CDAnimal) throws -> AnimalStatus {
        guard let value = AnimalStatus(rawValue: animal.statusRawValue) else {
            throw CoreDataAnimalRepositoryError.invalidAnimalStatusRawValue(
                animalID: animal.id,
                value: animal.statusRawValue
            )
        }
        return value
    }

    private static func pregnancyResult(_ check: CDPregnancyCheck) throws -> PregnancyResult {
        guard let value = PregnancyResult(rawValue: check.resultRawValue) else {
            throw CoreDataAnimalRepositoryError.invalidPregnancyResultRawValue(
                checkID: check.id,
                value: check.resultRawValue
            )
        }
        return value
    }

    private static func statusHistoryValue(
        _ rawValue: String,
        record: CDStatusRecord
    ) throws -> AnimalStatus {
        guard let value = AnimalStatus(rawValue: rawValue) else {
            throw CoreDataAnimalRepositoryError.invalidStatusHistoryRawValue(
                recordID: record.id,
                value: rawValue
            )
        }
        return value
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

    private static func timelineSort(
        _ lhs: TimelineProjectionEvent,
        _ rhs: TimelineProjectionEvent
    ) -> Bool {
        if lhs.event.date != rhs.event.date {
            return lhs.event.date > rhs.event.date
        }

        let localizedTitleOrder = lhs.event.title.localizedStandardCompare(rhs.event.title)
        if localizedTitleOrder != .orderedSame {
            return localizedTitleOrder == .orderedAscending
        }
        if lhs.event.title != rhs.event.title {
            return lhs.event.title < rhs.event.title
        }

        let lhsDetails = lhs.event.details ?? ""
        let rhsDetails = rhs.event.details ?? ""
        let localizedDetailsOrder = lhsDetails.localizedStandardCompare(rhsDetails)
        if localizedDetailsOrder != .orderedSame {
            return localizedDetailsOrder == .orderedAscending
        }
        if lhsDetails != rhsDetails {
            return lhsDetails < rhsDetails
        }

        let lhsTypeOrder = timelineTypeOrder(lhs.event.type)
        let rhsTypeOrder = timelineTypeOrder(rhs.event.type)
        if lhsTypeOrder != rhsTypeOrder {
            return lhsTypeOrder < rhsTypeOrder
        }

        if lhs.sourceID != rhs.sourceID {
            return lhs.sourceID.uuidString < rhs.sourceID.uuidString
        }

        return lhs.kindOrder < rhs.kindOrder
    }

    private static func timelineTypeOrder(_ type: AnimalTimelineEventType) -> Int {
        switch type {
        case .birth:
            return 0
        case .health:
            return 1
        case .pregnancy:
            return 2
        case .movement:
            return 3
        case .status:
            return 4
        case .tag:
            return 5
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
