@preconcurrency import CoreData
import Foundation

enum CoreDataAnimalPayloadCodec {
    static func encodeDistinguishingFeatures(
        _ features: [DistinguishingFeature]
    ) throws -> Data {
        try JSONEncoder().encode(features.normalizedDistinguishingFeatureOrder)
    }

    static func decodeDistinguishingFeatures(
        _ data: Data?,
        animalID: UUID
    ) throws -> [DistinguishingFeature] {
        guard let data else {
            throw CoreDataAnimalRepositoryError.corruptDistinguishingFeatures(
                animalID: animalID
            )
        }
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
        // Prefer the newest date, then the smallest persisted UUID on ties.
        // Match WorkingMapper.makeQueueItemEditorSnapshot's pregnancy-check ordering.
        let latestPregnancyCheck = pregnancyChecks.max { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
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
        let healthDates = try healthRecords.map { record in
            _ = try healthTreatment(record)
            return try healthDate(record)
        }
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
            pastureName: try animal.currentPasture.map { try $0.validatedName() },
            location: animal.activeWorkingSession == nil ? .pasture : .workingPen,
            lastPregnancyCheckDate: latestPregnancyCheck?.date,
            lastPregnancyStatus: pregnancyStatus(latestPregnancyResult),
            expectedCalvingDate: expectedCalvingDate,
            lastTreatmentDate: healthDates.max()
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
            .sorted { lhs, rhs in
                if lhs.birthDate != rhs.birthDate {
                    return lhs.birthDate > rhs.birthDate
                }
                let tagOrder = primaryTagFields(managedTags(lhs)).number.localizedStandardCompare(
                    primaryTagFields(managedTags(rhs)).number
                )
                if tagOrder != .orderedSame {
                    return tagOrder == .orderedAscending
                }
                return lhs.id.uuidString < rhs.id.uuidString
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
            pastureName: try animal.currentPasture.map { try $0.validatedName() },
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
            statusReferenceName: try animal.statusReference.map { try statusReferenceName($0) },
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

    static func statusReferenceName(_ reference: CDAnimalStatusReference) throws -> String {
        guard let name = reference.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoreDataAnimalStatusReferenceRepositoryError.invalidName(referenceID: reference.id)
        }
        return name
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
                    id: "birth:primary:\(animal.id.uuidString)",
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
                        id: "birth:offspring:\(offspring.id.uuidString)",
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
                        id: "health:\(record.id.uuidString)",
                        date: try healthDate(record),
                        type: .health,
                        title: try healthTreatment(record),
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
                        id: "pregnancy:\(check.id.uuidString)",
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
            guard let movementDate = movement.date else {
                throw CoreDataAnimalRepositoryError.missingMovementDate(recordID: movement.id)
            }
            events.append(
                TimelineProjectionEvent(
                    event: AnimalTimelineEvent(
                        id: "movement:\(movement.id.uuidString)",
                        date: movementDate,
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
            guard let statusDate = record.date else {
                throw CoreDataAnimalRepositoryError.missingStatusHistoryDate(recordID: record.id)
            }
            let oldStatus = try statusHistoryValue(record.oldStatusRawValue, record: record)
            let newStatus = try statusHistoryValue(record.newStatusRawValue, record: record)
            events.append(
                TimelineProjectionEvent(
                    event: AnimalTimelineEvent(
                        id: "status:\(record.id.uuidString)",
                        date: statusDate,
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
                        id: "tag:assigned:\(tag.id.uuidString)",
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
                            id: "tag:retired:\(tag.id.uuidString)",
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

    static func healthDate(_ record: CDHealthRecord) throws -> Date {
        guard let date = record.date else {
            throw CoreDataAnimalRepositoryError.missingHealthDate(recordID: record.id)
        }
        return date
    }

    static func healthTreatment(_ record: CDHealthRecord) throws -> String {
        guard let treatment = record.treatment else {
            throw CoreDataAnimalRepositoryError.corruptHealthTreatment(recordID: record.id)
        }
        return treatment
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
            hasCastrationOrBandingRecord: try managedHealthRecords(animal)
                .map { try healthTreatment($0) }
                .contains(where: AnimalTypeClassifier.isCastrationOrBandingTreatment),
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
        guard let rawValue = check.resultRawValue,
              let value = PregnancyResult(rawValue: rawValue) else {
            throw CoreDataAnimalRepositoryError.invalidPregnancyResultRawValue(
                checkID: check.id,
                value: check.resultRawValue ?? ""
            )
        }
        return value
    }

    static func statusHistoryValue(
        _ rawValue: String?,
        record: CDStatusRecord
    ) throws -> AnimalStatus {
        guard let rawValue, let value = AnimalStatus(rawValue: rawValue) else {
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


/// Shared Core Data relationship integrity boundary for direct Animal reads and M9 projections.
/// Kept outside the read-model actor so synchronous repository reads validate the same graph.
enum CoreDataAnimalReadGraphValidator {
    static func validateAnimalReadRelationships(
        _ animal: CDAnimal,
        herdID: UUID,
        validateOffspringSummaries: Bool = false
    ) throws {
        guard animal.herd.id == herdID else {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDAnimal.coreDataEntityName,
                id: animal.id,
                expectedHerdID: herdID,
                actualHerdID: animal.herd.id
            )
        }
        if let pasture = animal.currentPasture,
           pasture.herd.id != herdID {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDPasture.coreDataEntityName,
                id: pasture.id,
                expectedHerdID: herdID,
                actualHerdID: pasture.herd.id
            )
        }
        if let session = animal.activeWorkingSession,
           session.herd.id != herdID {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: CDWorkingSession.coreDataEntityName,
                id: session.id,
                expectedHerdID: herdID,
                actualHerdID: session.herd.id
            )
        }
        if let dam = animal.dam {
            guard dam.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDAnimal.coreDataEntityName,
                    id: dam.id,
                    expectedHerdID: herdID,
                    actualHerdID: dam.herd.id
                )
            }
            try validateTagRelationships(
                dam,
                herdID: herdID
            )
        }

        if let sire = animal.sire {
            try validateHerd(
                sire.herd.id, herdID: herdID,
                entity: CDAnimal.coreDataEntityName, id: sire.id
            )
            try validateTagRelationships(sire, herdID: herdID)
        }
        if let reference = animal.statusReference {
            try validateHerd(
                reference.herd.id, herdID: herdID,
                entity: CDAnimalStatusReference.coreDataEntityName, id: reference.id
            )
        }

        try validateTagRelationships(
            animal,
            herdID: herdID
        )
        for record in CoreDataAnimalProjection.managedHealthRecords(animal) {
            guard record.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDHealthRecord.coreDataEntityName,
                    id: record.id,
                    expectedHerdID: herdID,
                    actualHerdID: record.herd.id
                )
            }
            guard record.animal.objectID == animal.objectID else {
                throw CoreDataReadModelError.invalidAnimalRelationship(
                    entity: CDHealthRecord.coreDataEntityName,
                    id: record.id,
                    expectedAnimalID: animal.id,
                    actualAnimalID: record.animal.id
                )
            }
            if let session = record.workingSession {
                try validateHerd(
                    session.herd.id, herdID: herdID,
                    entity: CDWorkingSession.coreDataEntityName, id: session.id
                )
            }
        }
        for check in CoreDataAnimalProjection.managedPregnancyChecks(animal) {
            guard check.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDPregnancyCheck.coreDataEntityName,
                    id: check.id,
                    expectedHerdID: herdID,
                    actualHerdID: check.herd.id
                )
            }
            guard check.animal.objectID == animal.objectID else {
                throw CoreDataReadModelError.invalidAnimalRelationship(
                    entity: CDPregnancyCheck.coreDataEntityName,
                    id: check.id,
                    expectedAnimalID: animal.id,
                    actualAnimalID: check.animal.id
                )
            }
            if let sire = check.sire {
                try validateHerd(
                    sire.herd.id, herdID: herdID,
                    entity: CDAnimal.coreDataEntityName, id: sire.id
                )
            }
            if let session = check.workingSession {
                try validateHerd(
                    session.herd.id, herdID: herdID,
                    entity: CDWorkingSession.coreDataEntityName, id: session.id
                )
            }
        }
        for offspring in CoreDataAnimalProjection.managedMaternalOffspring(animal) {
            guard offspring.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDAnimal.coreDataEntityName,
                    id: offspring.id,
                    expectedHerdID: herdID,
                    actualHerdID: offspring.herd.id
                )
            }
            guard offspring.dam?.objectID == animal.objectID else {
                throw CoreDataReadModelError.invalidAnimalRelationship(
                    entity: CDAnimal.coreDataEntityName,
                    id: offspring.id,
                    expectedAnimalID: animal.id,
                    actualAnimalID: offspring.dam?.id
                )
            }
            if validateOffspringSummaries {
                try validateAnimalReadRelationships(
                    offspring, herdID: herdID
                )
            }
        }
        for movement in CoreDataAnimalProjection.managedMovementRecords(animal) {
            guard movement.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDMovementRecord.coreDataEntityName,
                    id: movement.id,
                    expectedHerdID: herdID,
                    actualHerdID: movement.herd.id
                )
            }
            guard movement.animal.objectID == animal.objectID else {
                throw CoreDataReadModelError.invalidAnimalRelationship(
                    entity: CDMovementRecord.coreDataEntityName,
                    id: movement.id,
                    expectedAnimalID: animal.id,
                    actualAnimalID: movement.animal.id
                )
            }
        }
        for statusRecord in CoreDataAnimalProjection.managedStatusRecords(animal) {
            guard statusRecord.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDStatusRecord.coreDataEntityName,
                    id: statusRecord.id,
                    expectedHerdID: herdID,
                    actualHerdID: statusRecord.herd.id
                )
            }
            guard statusRecord.animal.objectID == animal.objectID else {
                throw CoreDataReadModelError.invalidAnimalRelationship(
                    entity: CDStatusRecord.coreDataEntityName,
                    id: statusRecord.id,
                    expectedAnimalID: animal.id,
                    actualAnimalID: statusRecord.animal.id
                )
            }
        }
    }

    static func validateTagRelationships(
        _ animal: CDAnimal,
        herdID: UUID
    ) throws {
        let tags = CoreDataAnimalProjection.managedTags(animal)
        for tag in tags {
            guard tag.herd.id == herdID else {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDAnimalTag.coreDataEntityName,
                    id: tag.id,
                    expectedHerdID: herdID,
                    actualHerdID: tag.herd.id
                )
            }
            guard tag.animal?.objectID == animal.objectID else {
                throw CoreDataReadModelError.invalidAnimalRelationship(
                    entity: CDAnimalTag.coreDataEntityName,
                    id: tag.id,
                    expectedAnimalID: animal.id,
                    actualAnimalID: tag.animal?.id
                )
            }
            if let color = tag.color,
               color.herd.id != herdID {
                throw CoreDataReadModelError.invalidHerdOwnership(
                    entity: CDTagColorDefinition.coreDataEntityName,
                    id: color.id,
                    expectedHerdID: herdID,
                    actualHerdID: color.herd.id
                )
            }
        }

        let activeTags = tags.filter(\.isActive)
        guard activeTags.isEmpty || activeTags.filter(\.isPrimary).count == 1 else {
            throw CoreDataReadModelError.invalidActivePrimaryTagCardinality(
                animalID: animal.id,
                activeTagCount: activeTags.count,
                primaryTagCount: activeTags.filter(\.isPrimary).count
            )
        }
    }

    private static func validateHerd(
        _ actualHerdID: UUID,
        herdID: UUID,
        entity: String,
        id: UUID
    ) throws {
        guard actualHerdID == herdID else {
            throw CoreDataReadModelError.invalidHerdOwnership(
                entity: entity, id: id,
                expectedHerdID: herdID, actualHerdID: actualHerdID
            )
        }
    }
}
