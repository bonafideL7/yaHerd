@preconcurrency import CoreData
import Foundation

enum CoreDataAnimalRepositoryError: LocalizedError, Equatable, Sendable {
    case pastureNotFound(UUID)
    case parentNotFound(UUID)
    case statusReferenceNotFound(UUID)
    case tagColorNotFound(UUID)
    case existingTagOmitted(UUID)
    case corruptDistinguishingFeatures(animalID: UUID)

    var errorDescription: String? {
        switch self {
        case .pastureNotFound:
            return "The selected pasture could not be found."
        case .parentNotFound:
            return "The selected parent animal could not be found."
        case .statusReferenceNotFound:
            return "The selected status reference could not be found."
        case .tagColorNotFound:
            return "The selected tag color could not be found."
        case .existingTagOmitted:
            return "An existing tag is missing from the complete aggregate tag state."
        case .corruptDistinguishingFeatures:
            return "The animal's distinguishing-feature data is corrupt."
        }
    }
}

enum CoreDataAnimalMutation {
    static func fetchAnimals(
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> [CDAnimal] {
        let request = NSFetchRequest<CDAnimal>(entityName: CDAnimal.coreDataEntityName)
        request.predicate = NSPredicate(format: "herd == %@", herd)
        return try context.fetch(request)
    }

    static func fetchAnimals(
        ids: [UUID],
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> [CDAnimal] {
        let uniqueIDs = unique(ids)
        guard !uniqueIDs.isEmpty else {
            return []
        }
        let all = try fetchAnimals(herd: herd, in: context)
        let grouped = Dictionary(grouping: all, by: \.id)
        if let duplicate = grouped.first(where: { $0.value.count > 1 }) {
            throw CoreDataPersistenceError.duplicateApplicationID(
                entity: CDAnimal.coreDataEntityName,
                id: duplicate.key,
                herdID: herd.id
            )
        }
        return uniqueIDs.compactMap { grouped[$0]?.first }
    }

    static func resolvePasture(
        id: UUID?,
        herdID: UUID,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws -> CDPasture? {
        guard let id else {
            return nil
        }
        guard let pasture = try lookup.herdOwned(
            CDPasture.self,
            id: id,
            herdID: herdID,
            in: context
        ) else {
            throw CoreDataAnimalRepositoryError.pastureNotFound(id)
        }
        return pasture
    }

    static func resolveAnimal(
        id: UUID?,
        herdID: UUID,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws -> CDAnimal? {
        guard let id else {
            return nil
        }
        guard let animal = try lookup.herdOwned(
            CDAnimal.self,
            id: id,
            herdID: herdID,
            in: context
        ) else {
            throw CoreDataAnimalRepositoryError.parentNotFound(id)
        }
        return animal
    }

    static func resolveStatusReference(
        id: UUID?,
        herdID: UUID,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws -> CDAnimalStatusReference? {
        guard let id else {
            return nil
        }
        guard let reference = try lookup.herdOwned(
            CDAnimalStatusReference.self,
            id: id,
            herdID: herdID,
            in: context
        ) else {
            throw CoreDataAnimalRepositoryError.statusReferenceNotFound(id)
        }
        return reference
    }

    static func resolveTagColor(
        id: UUID?,
        herd: CDHerd,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws -> CDTagColorDefinition? {
        guard let id else {
            return nil
        }
        if let persisted = try lookup.herdOwned(
            CDTagColorDefinition.self,
            id: id,
            herdID: herd.id,
            in: context
        ) {
            return persisted
        }

        guard var builtIn = stableBuiltIns().first(where: { $0.id == id }) else {
            throw CoreDataAnimalRepositoryError.tagColorNotFound(id)
        }

        let colorRequest = NSFetchRequest<CDTagColorDefinition>(
            entityName: CDTagColorDefinition.coreDataEntityName
        )
        colorRequest.predicate = NSPredicate(format: "herd == %@", herd)
        let persistedColors = try context.fetch(colorRequest)
        if persistedColors.contains(where: { !$0.isHidden && $0.isDefault }) {
            builtIn.isDefault = false
        }

        let color = CDTagColorDefinition(context: context)
        color.id = builtIn.id
        color.name = builtIn.name
        color.prefix = builtIn.prefix
        color.red = builtIn.rgba.r
        color.green = builtIn.rgba.g
        color.blue = builtIn.rgba.b
        color.alpha = builtIn.rgba.a
        color.sortOrder = Int64(builtIn.sortOrder)
        color.isHidden = false
        color.isDefault = builtIn.isDefault
        color.createdAt = builtIn.createdAt
        color.updatedAt = builtIn.updatedAt
        color.herd = herd
        return color
    }

    static func validateAnimal(
        birthDate: Date,
        status: AnimalStatus,
        saleDate: Date?,
        deathDate: Date?,
        animalID: UUID?,
        sire: CDAnimal?,
        dam: CDAnimal?
    ) throws {
        try ValidationService.validateAnimal(
            ValidationService.AnimalValidationRules(
                birthDate: birthDate,
                status: status,
                saleDate: saleDate,
                deathDate: deathDate,
                animalID: animalID,
                sireID: sire?.id,
                sireSex: sire.map { Sex(rawValue: $0.sexRawValue) ?? .unknown },
                damID: dam?.id,
                damSex: dam.map { Sex(rawValue: $0.sexRawValue) ?? .unknown }
            )
        )
    }

    static func validateTagState(_ tags: [AnimalTagTransactionState]) throws {
        guard Set(tags.map(\.id)).count == tags.count else {
            throw AnimalAggregateTransactionError.duplicateTagApplicationIDs
        }

        let activeTags = tags.filter(\.isActive)
        let activePrimaryCount = activeTags.filter(\.isPrimary).count

        if tags.contains(where: { !$0.isActive && $0.isPrimary }) {
            throw AnimalAggregateTransactionError.inactiveTagCannotBePrimary
        }
        if !activeTags.isEmpty && activePrimaryCount == 0 {
            throw AnimalAggregateTransactionError.activeTagsRequirePrimary
        }
        if activePrimaryCount > 1 {
            throw AnimalAggregateTransactionError.multipleActivePrimaryTags
        }
    }

    static func aggregateAttributes(_ animal: CDAnimal) throws -> AnimalAggregateAttributes {
        AnimalAggregateAttributes(
            name: animal.name,
            sex: Sex(rawValue: animal.sexRawValue) ?? .unknown,
            birthDate: animal.birthDate,
            status: AnimalStatus(rawValue: animal.statusRawValue) ?? .active,
            pastureID: animal.currentPasture?.id,
            sireID: animal.sire?.id,
            damID: animal.dam?.id,
            distinguishingFeatures: try CoreDataAnimalProjection.distinguishingFeatures(animal)
                .normalizedDistinguishingFeatureOrder,
            saleDate: animal.saleDate,
            salePrice: animal.salePrice?.doubleValue,
            reasonSold: animal.reasonSold,
            deathDate: animal.deathDate,
            causeOfDeath: animal.causeOfDeath,
            statusReferenceID: animal.statusReference?.id
        )
    }

    static func aggregateTagStates(_ animal: CDAnimal) -> [AnimalTagTransactionState] {
        CoreDataAnimalProjection.managedTags(animal)
            .map {
                AnimalTagTransactionState(
                    id: $0.id,
                    number: $0.number,
                    colorID: $0.color?.id,
                    isPrimary: $0.isPrimary,
                    isActive: $0.isActive
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    static func applyAggregateAttributes(
        _ attributes: AnimalAggregateAttributes,
        to animal: CDAnimal,
        herd: CDHerd,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext,
        mutationDate: Date
    ) throws -> Bool {
        let oldAttributes = try aggregateAttributes(animal)
        let oldStatus = AnimalStatus(rawValue: animal.statusRawValue) ?? .active
        let oldPasture = animal.currentPasture

        let pasture = try resolvePasture(
            id: attributes.pastureID,
            herdID: herd.id,
            lookup: lookup,
            in: context
        )
        let sire = try resolveAnimal(
            id: attributes.sireID,
            herdID: herd.id,
            lookup: lookup,
            in: context
        )
        let dam = try resolveAnimal(
            id: attributes.damID,
            herdID: herd.id,
            lookup: lookup,
            in: context
        )
        let statusReference = try resolveStatusReference(
            id: attributes.statusReferenceID,
            herdID: herd.id,
            lookup: lookup,
            in: context
        )

        try validateAnimal(
            birthDate: attributes.birthDate,
            status: attributes.status,
            saleDate: attributes.saleDate,
            deathDate: attributes.deathDate,
            animalID: animal.id,
            sire: sire,
            dam: dam
        )

        animal.name = attributes.name
        animal.sexRawValue = attributes.sex.rawValue
        animal.birthDate = attributes.birthDate
        animal.sire = sire
        animal.dam = dam
        animal.distinguishingFeaturesData = try JSONEncoder().encode(
            attributes.distinguishingFeatures.normalizedDistinguishingFeatureOrder
        )
        animal.statusReference = statusReference

        let normalizedStatus = AnimalStatusTransitionService.normalizedState(
            status: attributes.status,
            saleDate: attributes.saleDate,
            salePrice: attributes.salePrice,
            reasonSold: attributes.reasonSold,
            deathDate: attributes.deathDate,
            causeOfDeath: attributes.causeOfDeath,
            statusReferenceID: attributes.statusReferenceID,
            effectiveDate: AnimalStatusTransitionService.effectiveDate(
                for: attributes.status,
                saleDate: attributes.saleDate,
                deathDate: attributes.deathDate,
                now: mutationDate
            )
        )
        applyStatusState(normalizedStatus, reference: statusReference, to: animal)

        if oldPasture?.id != pasture?.id {
            try move(
                animal,
                to: pasture,
                herd: herd,
                in: context,
                at: mutationDate
            )
        }

        if oldStatus != attributes.status {
            try appendStatusRecord(
                animal: animal,
                oldStatus: oldStatus,
                newStatus: attributes.status,
                herd: herd,
                in: context,
                at: mutationDate
            )
        }

        return oldAttributes != (try aggregateAttributes(animal))
    }

    static func reconcileAggregateTags(
        _ desired: [AnimalTagTransactionState],
        for animal: CDAnimal,
        herd: CDHerd,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext,
        mutationDate: Date
    ) throws -> Bool {
        try validateTagState(desired)

        let existing = CoreDataAnimalProjection.managedTags(animal)
        let desiredIDs = Set(desired.map(\.id))
        for tag in existing where !desiredIDs.contains(tag.id) {
            throw CoreDataAnimalRepositoryError.existingTagOmitted(tag.id)
        }

        let before = aggregateTagStates(animal)
        let existingGroups = Dictionary(grouping: existing, by: \.id)
        if let duplicate = existingGroups.first(where: { $0.value.count > 1 }) {
            throw CoreDataPersistenceError.duplicateApplicationID(
                entity: CDAnimalTag.coreDataEntityName,
                id: duplicate.key,
                herdID: herd.id
            )
        }
        let existingByID = existingGroups.compactMapValues(\.first)

        for state in desired {
            let color = try resolveTagColor(
                id: state.colorID,
                herd: herd,
                lookup: lookup,
                in: context
            )

            if let tag = existingByID[state.id] {
                let wasActive = tag.isActive
                tag.number = state.number
                tag.color = color
                tag.isPrimary = state.isPrimary
                tag.isActive = state.isActive

                if state.isActive {
                    tag.removedAt = nil
                } else if wasActive {
                    tag.removedAt = mutationDate
                } else if tag.removedAt == nil {
                    tag.removedAt = mutationDate
                }
            } else {
                if try lookup.herdOwned(
                    CDAnimalTag.self,
                    id: state.id,
                    herdID: herd.id,
                    in: context
                ) != nil {
                    throw CoreDataPersistenceError.duplicateApplicationID(
                        entity: CDAnimalTag.coreDataEntityName,
                        id: state.id,
                        herdID: herd.id
                    )
                }

                let tag = CDAnimalTag(context: context)
                tag.id = state.id
                tag.number = state.number
                tag.isPrimary = state.isPrimary
                tag.isActive = state.isActive
                tag.assignedAt = mutationDate
                tag.removedAt = state.isActive ? nil : mutationDate
                tag.color = color
                tag.animal = animal
                tag.herd = herd
            }
        }

        return before != aggregateTagStates(animal)
    }

    static func move(
        _ animal: CDAnimal,
        to pasture: CDPasture?,
        herd: CDHerd,
        in context: NSManagedObjectContext,
        at date: Date
    ) throws {
        let source = animal.currentPasture
        guard source?.id != pasture?.id else {
            return
        }

        let movement = CDMovementRecord(context: context)
        movement.id = try uniqueID(
            for: CDMovementRecord.self,
            herdID: herd.id,
            lookup: CoreDataLookup(),
            in: context
        )
        movement.date = date
        movement.fromPastureIDSnapshot = source?.id
        movement.fromPastureNameSnapshot = source?.name
        movement.toPastureIDSnapshot = pasture?.id
        movement.toPastureNameSnapshot = pasture?.name
        movement.herd = herd
        movement.animal = animal

        animal.currentPasture = pasture
        animal.activeWorkingSession = nil
    }

    static func appendStatusRecord(
        animal: CDAnimal,
        oldStatus: AnimalStatus,
        newStatus: AnimalStatus,
        herd: CDHerd,
        in context: NSManagedObjectContext,
        at date: Date
    ) throws {
        guard oldStatus != newStatus else {
            return
        }

        let record = CDStatusRecord(context: context)
        record.id = try uniqueID(
            for: CDStatusRecord.self,
            herdID: herd.id,
            lookup: CoreDataLookup(),
            in: context
        )
        record.date = date
        record.oldStatusRawValue = oldStatus.rawValue
        record.newStatusRawValue = newStatus.rawValue
        record.herd = herd
        record.animal = animal
    }

    static func applyStatusState(
        _ state: AnimalStatusState,
        reference: CDAnimalStatusReference?,
        to animal: CDAnimal
    ) {
        animal.statusRawValue = state.status.rawValue
        animal.saleDate = state.saleDate
        animal.salePrice = state.salePrice.map(NSNumber.init(value:))
        animal.reasonSold = state.reasonSold
        animal.deathDate = state.deathDate
        animal.causeOfDeath = state.causeOfDeath
        animal.statusReference = reference
    }

    static func applyArchiveState(
        _ state: AnimalArchiveState,
        to animal: CDAnimal
    ) -> Bool {
        let changed = animal.isArchived != state.isArchived
            || animal.archivedAt != state.archivedAt
            || animal.archiveReason != state.reason

        animal.isArchived = state.isArchived
        animal.archivedAt = state.archivedAt
        animal.archiveReason = state.reason
        return changed
    }

    static func enforceActivePrimary(
        in tags: [CDAnimalTag],
        preferredPrimaryID: UUID? = nil,
        excludedFallbackID: UUID? = nil
    ) {
        let active = tags.filter(\.isActive)
        guard !active.isEmpty else {
            for tag in tags {
                tag.isPrimary = false
            }
            return
        }

        if let preferredPrimaryID,
           active.contains(where: { $0.id == preferredPrimaryID }) {
            for tag in tags {
                tag.isPrimary = tag.isActive && tag.id == preferredPrimaryID
            }
            return
        }

        let actualPrimaries = active.filter(\.isPrimary)
        if actualPrimaries.count == 1 {
            for tag in tags where !tag.isActive {
                tag.isPrimary = false
            }
            return
        }

        let fallbackPool: [CDAnimalTag]
        let excludingRequested = active.filter { $0.id != excludedFallbackID }
        fallbackPool = excludingRequested.isEmpty ? active : excludingRequested

        let orderedIDs = AnimalTagService.activeTags(
            fallbackPool.map(CoreDataAnimalProjection.tagState)
        ).map(\.id)
        let selectedID = orderedIDs.first

        for tag in tags {
            tag.isPrimary = tag.isActive && tag.id == selectedID
        }
    }

    static func rotateRevision(_ animal: CDAnimal) {
        animal.editorRevision = UUID()
    }

    static func uniqueID<Object>(
        for type: Object.Type,
        herdID: UUID,
        lookup: CoreDataLookup,
        in context: NSManagedObjectContext
    ) throws -> UUID
    where Object: NSManagedObject & CoreDataHerdOwnedManagedObject {
        while true {
            let id = UUID()
            if try lookup.herdOwned(
                type,
                id: id,
                herdID: herdID,
                in: context
            ) == nil {
                return id
            }
        }
    }

    static func inferSingleSire(
        pastureID: UUID?,
        excluding excludedAnimalID: UUID?,
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> CDAnimal? {
        guard let pastureID else {
            return nil
        }

        let animals = try fetchAnimals(herd: herd, in: context)
        let candidates = animals.map {
            AnimalSireCandidate(
                id: $0.id,
                pastureID: $0.currentPasture?.id,
                sex: Sex(rawValue: $0.sexRawValue) ?? .unknown,
                birthDate: $0.birthDate,
                status: AnimalStatus(rawValue: $0.statusRawValue) ?? .active,
                isArchived: $0.isArchived,
                animalType: CoreDataAnimalProjection.animalType($0)
            )
        }

        guard let inferredID = AnimalSireInferencePolicy().inferSireID(
            from: candidates,
            pastureID: pastureID,
            excluding: excludedAnimalID
        ) else {
            return nil
        }
        return animals.first { $0.id == inferredID }
    }

    static func stableBuiltIns() -> [TagColorSnapshot] {
        let stableTimestamp = Date(timeIntervalSince1970: 0)
        return TagColorDefaults.seedDefaultColors().map {
            var snapshot = $0
            snapshot.createdAt = stableTimestamp
            snapshot.updatedAt = stableTimestamp
            return snapshot
        }
    }

    static func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
