@preconcurrency import CoreData
import Foundation

@MainActor
final class CoreDataAnimalRepository:
    AnimalRepository,
    AnimalAggregateEditReading,
    AnimalAggregateTransactionWriting
{
    private let selection: any CurrentHerdSelectionReading
    private let contextFactory: CoreDataContextFactory
    private let statusReferenceRepository: CoreDataAnimalStatusReferenceRepository
    private nonisolated let lookup: CoreDataLookup

    init(
        selection: any CurrentHerdSelectionReading,
        contextFactory: CoreDataContextFactory,
        lookup: CoreDataLookup
    ) {
        self.selection = selection
        self.contextFactory = contextFactory
        self.statusReferenceRepository = CoreDataAnimalStatusReferenceRepository(
            selection: selection,
            contextFactory: contextFactory,
            lookup: lookup
        )
        self.lookup = lookup
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            selection: selection,
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup
        )
    }

    // MARK: - Reads

    func fetchAnimals() throws -> [AnimalSummary] {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            return try CoreDataAnimalMutation.fetchAnimals(herd: herd, in: context)
                .map { try CoreDataAnimalProjection.summary($0) }
        }
    }

    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard try lookup.herd(id: herdID, in: context) != nil else {
                throw HerdRepositoryError.missingHerd
            }
            guard let animal = try lookup.herdOwned(
                CDAnimal.self,
                id: id,
                herdID: herdID,
                in: context
            ) else {
                return nil
            }
            return try CoreDataAnimalProjection.detail(animal)
        }
    }

    func fetchTimeline(id: UUID) throws -> [AnimalTimelineEvent] {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard try lookup.herd(id: herdID, in: context) != nil else {
                throw HerdRepositoryError.missingHerd
            }
            guard let animal = try lookup.herdOwned(
                CDAnimal.self,
                id: id,
                herdID: herdID,
                in: context
            ) else {
                return []
            }
            return try CoreDataAnimalProjection.timeline(animal)
        }
    }

    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] {
        try statusReferenceRepository.fetchStatusReferenceOptions()
    }

    func fetchParentOptions(
        excluding excludedAnimalID: UUID?
    ) throws -> [AnimalParentOption] {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            return try CoreDataAnimalMutation.fetchAnimals(herd: herd, in: context)
                .filter { !$0.isArchived && $0.id != excludedAnimalID }
                .map { try CoreDataAnimalProjection.parentOption($0) }
                .sorted {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
        }
    }

    func fetchOffspringDraftSeed(
        forDamID damID: UUID
    ) throws -> OffspringDraftSeed? {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            guard let dam = try lookup.herdOwned(
                CDAnimal.self,
                id: damID,
                herdID: herdID,
                in: context
            ), !dam.isArchived else {
                return nil
            }

            let inferredSire = try CoreDataAnimalMutation.inferSingleSire(
                pastureID: dam.currentPasture?.id,
                excluding: dam.id,
                herd: herd,
                in: context
            )
            return OffspringDraftSeed(
                damID: dam.id,
                damDisplayName: try CoreDataAnimalProjection.parentOption(dam).displayName,
                pastureID: dam.currentPasture?.id,
                pastureName: dam.currentPasture?.name,
                inferredSireID: inferredSire?.id,
                inferredSireDisplayName: try inferredSire.map {
                    try CoreDataAnimalProjection.parentOption($0).displayName
                },
                defaultBirthDate: Calendar.current.startOfDay(for: .now)
            )
        }
    }

    func fetchAnimalAggregateForEditing(
        id: UUID
    ) throws -> AnimalAggregateEditSnapshot? {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard try lookup.herd(id: herdID, in: context) != nil else {
                throw HerdRepositoryError.missingHerd
            }
            guard let animal = try lookup.herdOwned(
                CDAnimal.self,
                id: id,
                herdID: herdID,
                in: context
            ) else {
                return nil
            }
            return AnimalAggregateEditSnapshot(
                animal: try CoreDataAnimalProjection.detail(animal),
                revision: AnimalAggregateRevision(value: animal.editorRevision)
            )
        }
    }

    // MARK: - Legacy Animal repository writes

    func create(input: AnimalInput) throws -> AnimalDetailSnapshot {
        try performWrite { context, herd in
            let pasture = try CoreDataAnimalMutation.resolvePasture(
                id: input.pastureID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            let dam = try CoreDataAnimalMutation.resolveAnimal(
                id: input.damID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            let explicitSire = try CoreDataAnimalMutation.resolveAnimal(
                id: input.sireID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            let sire = explicitSire ?? (dam == nil ? nil : try CoreDataAnimalMutation.inferSingleSire(
                pastureID: pasture?.id ?? dam?.currentPasture?.id,
                excluding: input.damID,
                herd: herd,
                in: context
            ))
            let statusReference = try CoreDataAnimalMutation.resolveStatusReference(
                id: input.statusReferenceID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )

            try CoreDataAnimalMutation.validateAnimal(
                birthDate: input.birthDate,
                status: input.status,
                saleDate: input.saleDate,
                deathDate: input.deathDate,
                animalID: nil,
                sire: sire,
                dam: dam
            )

            let animal = CDAnimal(context: context)
            animal.id = try CoreDataAnimalMutation.uniqueID(
                for: CDAnimal.self,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            animal.editorRevision = UUID()
            animal.name = input.name
            animal.sexRawValue = input.sex.rawValue
            animal.birthDate = input.birthDate
            animal.distinguishingFeaturesData = try CoreDataAnimalPayloadCodec.encodeDistinguishingFeatures(
                input.distinguishingFeatures
            )
            animal.isArchived = false
            animal.archivedAt = nil
            animal.archiveReason = nil
            animal.herd = herd
            animal.currentPasture = pasture
            animal.sire = sire
            animal.dam = dam
            animal.activeWorkingSession = nil

            let normalizedStatus = AnimalStatusTransitionService.normalizedState(
                status: input.status,
                saleDate: input.saleDate,
                salePrice: input.salePrice,
                reasonSold: input.reasonSold,
                deathDate: input.deathDate,
                causeOfDeath: input.causeOfDeath,
                statusReferenceID: input.statusReferenceID,
                effectiveDate: AnimalStatusTransitionService.effectiveDate(
                    for: input.status,
                    saleDate: input.saleDate,
                    deathDate: input.deathDate
                )
            )
            CoreDataAnimalMutation.applyStatusState(
                normalizedStatus,
                reference: statusReference,
                to: animal
            )

            let tagNumber = input.tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tagNumber.isEmpty {
                let tag = CDAnimalTag(context: context)
                tag.id = try CoreDataAnimalMutation.uniqueID(
                    for: CDAnimalTag.self,
                    herdID: herd.id,
                    lookup: self.lookup,
                    in: context
                )
                tag.number = tagNumber
                tag.isPrimary = true
                tag.isActive = true
                tag.assignedAt = .now
                tag.removedAt = nil
                tag.color = try CoreDataAnimalMutation.resolveTagColor(
                    id: input.tagColorID,
                    herd: herd,
                    lookup: self.lookup,
                    in: context
                )
                tag.herd = herd
                tag.animal = animal
            }

            return try CoreDataAnimalProjection.detail(animal)
        }
    }

    func update(
        id: UUID,
        input: AnimalInput
    ) throws -> AnimalDetailSnapshot {
        try performWrite { context, herd in
            guard let animal = try self.lookup.herdOwned(
                CDAnimal.self,
                id: id,
                herdID: herd.id,
                in: context
            ) else {
                throw AnimalValidationError.animalNotFound
            }

            let beforeAttributes = try CoreDataAnimalMutation.aggregateAttributes(animal)
            let beforeTags = CoreDataAnimalMutation.aggregateTagStates(animal)
            let oldStatus = try CoreDataAnimalProjection.status(animal)
            let oldPasture = animal.currentPasture

            let pasture = try CoreDataAnimalMutation.resolvePasture(
                id: input.pastureID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            let dam = try CoreDataAnimalMutation.resolveAnimal(
                id: input.damID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            let explicitSire = try CoreDataAnimalMutation.resolveAnimal(
                id: input.sireID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            let sire = explicitSire ?? (dam == nil ? nil : try CoreDataAnimalMutation.inferSingleSire(
                pastureID: pasture?.id ?? dam?.currentPasture?.id,
                excluding: input.damID,
                herd: herd,
                in: context
            ))
            let statusReference = try CoreDataAnimalMutation.resolveStatusReference(
                id: input.statusReferenceID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )

            try CoreDataAnimalMutation.validateAnimal(
                birthDate: input.birthDate,
                status: input.status,
                saleDate: input.saleDate,
                deathDate: input.deathDate,
                animalID: id,
                sire: sire,
                dam: dam
            )

            animal.name = input.name
            animal.sexRawValue = input.sex.rawValue
            animal.birthDate = input.birthDate
            animal.sire = sire
            animal.dam = dam
            animal.distinguishingFeaturesData = try CoreDataAnimalPayloadCodec.encodeDistinguishingFeatures(
                input.distinguishingFeatures
            )

            let normalizedStatus = AnimalStatusTransitionService.normalizedState(
                status: input.status,
                saleDate: input.saleDate,
                salePrice: input.salePrice,
                reasonSold: input.reasonSold,
                deathDate: input.deathDate,
                causeOfDeath: input.causeOfDeath,
                statusReferenceID: input.statusReferenceID,
                effectiveDate: AnimalStatusTransitionService.effectiveDate(
                    for: input.status,
                    saleDate: input.saleDate,
                    deathDate: input.deathDate
                )
            )
            CoreDataAnimalMutation.applyStatusState(
                normalizedStatus,
                reference: statusReference,
                to: animal
            )

            let mutationDate = Date()
            if oldPasture?.id != pasture?.id {
                try CoreDataAnimalMutation.move(
                    animal,
                    to: pasture,
                    herd: herd,
                    in: context,
                    at: mutationDate
                )
            }
            if oldStatus != input.status {
                try CoreDataAnimalMutation.appendStatusRecord(
                    animal: animal,
                    oldStatus: oldStatus,
                    newStatus: input.status,
                    herd: herd,
                    in: context,
                    at: mutationDate
                )
            }

            try self.reconcileLegacyPrimaryTag(
                animal: animal,
                number: input.tagNumber,
                colorID: input.tagColorID,
                herd: herd,
                context: context,
                at: mutationDate
            )

            if beforeAttributes != (try CoreDataAnimalMutation.aggregateAttributes(animal))
                || beforeTags != CoreDataAnimalMutation.aggregateTagStates(animal) {
                CoreDataAnimalMutation.rotateRevision(animal)
            }

            return try CoreDataAnimalProjection.detail(animal)
        }
    }

    func delete(ids: [UUID]) throws {
        let ids = CoreDataAnimalMutation.unique(ids)
        guard !ids.isEmpty else {
            return
        }

        try performWrite { context, herd in
            let targets = try CoreDataAnimalMutation.fetchAnimals(
                ids: ids,
                herd: herd,
                in: context
            )
            let targetIDs = Set(targets.map(\.id))
            guard !targetIDs.isEmpty else {
                return
            }

            var affectedSurvivors: [UUID: CDAnimal] = [:]
            for animal in try CoreDataAnimalMutation.fetchAnimals(herd: herd, in: context)
                where !targetIDs.contains(animal.id) {
                var changed = false
                if let sireID = animal.sire?.id, targetIDs.contains(sireID) {
                    animal.sire = nil
                    changed = true
                }
                if let damID = animal.dam?.id, targetIDs.contains(damID) {
                    animal.dam = nil
                    changed = true
                }
                if changed {
                    affectedSurvivors[animal.id] = animal
                }
            }

            for survivor in affectedSurvivors.values {
                CoreDataAnimalMutation.rotateRevision(survivor)
            }
            for target in targets {
                context.delete(target)
            }
        }
    }

    func archive(ids: [UUID]) throws {
        let ids = CoreDataAnimalMutation.unique(ids)
        guard !ids.isEmpty else {
            return
        }
        let date = Date()
        try performWrite { context, herd in
            for animal in try CoreDataAnimalMutation.fetchAnimals(ids: ids, herd: herd, in: context) {
                _ = CoreDataAnimalMutation.applyArchiveState(
                    AnimalArchiveService.archived(reason: nil, at: date),
                    to: animal
                )
            }
        }
    }

    func restore(ids: [UUID]) throws {
        let ids = CoreDataAnimalMutation.unique(ids)
        guard !ids.isEmpty else {
            return
        }
        try performWrite { context, herd in
            for animal in try CoreDataAnimalMutation.fetchAnimals(ids: ids, herd: herd, in: context) {
                _ = CoreDataAnimalMutation.applyArchiveState(
                    AnimalArchiveService.restored(),
                    to: animal
                )
            }
        }
    }

    func move(
        ids: [UUID],
        toPastureID: UUID?
    ) throws {
        let ids = CoreDataAnimalMutation.unique(ids)
        guard !ids.isEmpty else {
            return
        }
        let date = Date()
        try performWrite { context, herd in
            let pasture = try CoreDataAnimalMutation.resolvePasture(
                id: toPastureID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            for animal in try CoreDataAnimalMutation.fetchAnimals(ids: ids, herd: herd, in: context) {
                guard animal.currentPasture?.id != pasture?.id else {
                    continue
                }
                try CoreDataAnimalMutation.move(
                    animal,
                    to: pasture,
                    herd: herd,
                    in: context,
                    at: date
                )
                CoreDataAnimalMutation.rotateRevision(animal)
            }
        }
    }

    func addTag(
        animalID: UUID,
        input: AnimalTagInput
    ) throws -> AnimalDetailSnapshot {
        try performWrite { context, herd in
            let animal = try self.requiredAnimal(
                id: animalID,
                herdID: herd.id,
                context: context
            )
            let tags = CoreDataAnimalProjection.managedTags(animal)
            let shouldBePrimary = AnimalTagService.shouldMakeAddedTagPrimary(
                isPrimary: input.isPrimary,
                existingTags: tags.map(CoreDataAnimalProjection.tagState)
            )
            let tag = CDAnimalTag(context: context)
            tag.id = try CoreDataAnimalMutation.uniqueID(
                for: CDAnimalTag.self,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            tag.number = input.number.trimmingCharacters(in: .whitespacesAndNewlines)
            tag.isPrimary = shouldBePrimary
            tag.isActive = true
            tag.assignedAt = .now
            tag.removedAt = nil
            tag.color = try CoreDataAnimalMutation.resolveTagColor(
                id: input.colorID,
                herd: herd,
                lookup: self.lookup,
                in: context
            )
            tag.herd = herd
            tag.animal = animal
            CoreDataAnimalMutation.enforceActivePrimary(
                in: CoreDataAnimalProjection.managedTags(animal),
                preferredPrimaryID: shouldBePrimary ? tag.id : nil
            )
            CoreDataAnimalMutation.rotateRevision(animal)
            return try CoreDataAnimalProjection.detail(animal)
        }
    }

    func updateTag(
        animalID: UUID,
        tagID: UUID,
        input: AnimalTagInput
    ) throws -> AnimalDetailSnapshot {
        try performWrite { context, herd in
            let animal = try self.requiredAnimal(
                id: animalID,
                herdID: herd.id,
                context: context
            )
            guard let tag = CoreDataAnimalProjection.managedTags(animal)
                .first(where: { $0.id == tagID }) else {
                throw AnimalValidationError.animalTagNotFound
            }

            let before = CoreDataAnimalMutation.aggregateTagStates(animal)
            tag.number = input.number.trimmingCharacters(in: .whitespacesAndNewlines)
            tag.color = try CoreDataAnimalMutation.resolveTagColor(
                id: input.colorID,
                herd: herd,
                lookup: self.lookup,
                in: context
            )

            let tags = CoreDataAnimalProjection.managedTags(animal)
            if tag.isActive {
                if input.isPrimary {
                    CoreDataAnimalMutation.enforceActivePrimary(
                        in: tags,
                        preferredPrimaryID: tag.id
                    )
                } else {
                    tag.isPrimary = false
                    CoreDataAnimalMutation.enforceActivePrimary(
                        in: tags,
                        excludedFallbackID: tag.id
                    )
                }
            } else {
                tag.isPrimary = false
                CoreDataAnimalMutation.enforceActivePrimary(in: tags)
            }

            if before != CoreDataAnimalMutation.aggregateTagStates(animal) {
                CoreDataAnimalMutation.rotateRevision(animal)
            }
            return try CoreDataAnimalProjection.detail(animal)
        }
    }

    func promoteTag(
        animalID: UUID,
        tagID: UUID
    ) throws -> AnimalDetailSnapshot {
        try performWrite { context, herd in
            let animal = try self.requiredAnimal(
                id: animalID,
                herdID: herd.id,
                context: context
            )
            guard let tag = CoreDataAnimalProjection.managedTags(animal)
                .first(where: { $0.id == tagID }) else {
                throw AnimalValidationError.animalTagNotFound
            }

            let before = CoreDataAnimalMutation.aggregateTagStates(animal)
            tag.isActive = true
            tag.removedAt = nil
            CoreDataAnimalMutation.enforceActivePrimary(
                in: CoreDataAnimalProjection.managedTags(animal),
                preferredPrimaryID: tag.id
            )

            if before != CoreDataAnimalMutation.aggregateTagStates(animal) {
                CoreDataAnimalMutation.rotateRevision(animal)
            }
            return try CoreDataAnimalProjection.detail(animal)
        }
    }

    func retireTag(
        animalID: UUID,
        tagID: UUID
    ) throws -> AnimalDetailSnapshot {
        try performWrite { context, herd in
            let animal = try self.requiredAnimal(
                id: animalID,
                herdID: herd.id,
                context: context
            )
            let tags = CoreDataAnimalProjection.managedTags(animal)
            guard let tag = tags.first(where: { $0.id == tagID }) else {
                throw AnimalValidationError.animalTagNotFound
            }

            let before = CoreDataAnimalMutation.aggregateTagStates(animal)
            let replacementID = AnimalTagService.replacementPrimaryTagID(
                afterRetiring: tag.id,
                from: tags.map(CoreDataAnimalProjection.tagState)
            )
            tag.isActive = false
            tag.isPrimary = false
            if tag.removedAt == nil {
                tag.removedAt = .now
            }

            if let replacementID,
               let replacement = tags.first(where: { $0.id == replacementID }) {
                replacement.isActive = true
                replacement.removedAt = nil
            }
            CoreDataAnimalMutation.enforceActivePrimary(
                in: tags,
                preferredPrimaryID: replacementID
            )

            if before != CoreDataAnimalMutation.aggregateTagStates(animal) {
                CoreDataAnimalMutation.rotateRevision(animal)
            }
            return try CoreDataAnimalProjection.detail(animal)
        }
    }

    func addHealthRecord(
        animalID: UUID,
        input: HealthRecordInput
    ) throws -> AnimalDetailSnapshot {
        try ValidationService.validateHealthRecord(treatment: input.treatment)
        return try performWrite { context, herd in
            let animal = try self.requiredAnimal(
                id: animalID,
                herdID: herd.id,
                context: context
            )
            let record = CDHealthRecord(context: context)
            record.id = try CoreDataAnimalMutation.uniqueID(
                for: CDHealthRecord.self,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            record.date = input.date
            record.treatment = input.treatment
            record.notes = input.notes
            record.herd = herd
            record.animal = animal
            record.workingSession = nil
            return try CoreDataAnimalProjection.detail(animal)
        }
    }

    func addPregnancyCheck(
        animalID: UUID,
        input: PregnancyCheckInput
    ) throws -> AnimalDetailSnapshot {
        try ValidationService.validatePregCheck()
        return try performWrite { context, herd in
            let animal = try self.requiredAnimal(
                id: animalID,
                herdID: herd.id,
                context: context
            )
            let sire = try CoreDataAnimalMutation.resolveAnimal(
                id: input.sireAnimalID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            let check = CDPregnancyCheck(context: context)
            check.id = try CoreDataAnimalMutation.uniqueID(
                for: CDPregnancyCheck.self,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            check.date = input.date
            check.resultRawValue = input.result.rawValue
            check.technician = input.technician
            check.estimatedDaysPregnant = input.estimatedDaysPregnant.map(NSNumber.init(value:))
            check.dueDate = input.dueDate
            check.herd = herd
            check.animal = animal
            check.sire = sire
            check.workingSession = nil
            return try CoreDataAnimalProjection.detail(animal)
        }
    }

    // MARK: - Atomic aggregate transaction boundary

    func createAnimal(
        _ transaction: CreateAnimalAggregateTransaction
    ) throws -> AnimalAggregateEditSnapshot {
        try CoreDataAnimalMutation.validateTagState(transaction.tags)
        let mutationDate = Date()

        return try performWrite { context, herd in
            if try self.lookup.herdOwned(
                CDAnimal.self,
                id: transaction.animalID,
                herdID: herd.id,
                in: context
            ) != nil {
                throw CoreDataPersistenceError.duplicateApplicationID(
                    entity: CDAnimal.coreDataEntityName,
                    id: transaction.animalID,
                    herdID: herd.id
                )
            }

            let attributes = transaction.attributes
            let pasture = try CoreDataAnimalMutation.resolvePasture(
                id: attributes.pastureID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            let sire = try CoreDataAnimalMutation.resolveAnimal(
                id: attributes.sireID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            let dam = try CoreDataAnimalMutation.resolveAnimal(
                id: attributes.damID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            let statusReference = try CoreDataAnimalMutation.resolveStatusReference(
                id: attributes.statusReferenceID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            try CoreDataAnimalMutation.validateAnimal(
                birthDate: attributes.birthDate,
                status: attributes.status,
                saleDate: attributes.saleDate,
                deathDate: attributes.deathDate,
                animalID: transaction.animalID,
                sire: sire,
                dam: dam
            )

            let animal = CDAnimal(context: context)
            animal.id = transaction.animalID
            animal.editorRevision = UUID()
            animal.name = attributes.name
            animal.sexRawValue = attributes.sex.rawValue
            animal.birthDate = attributes.birthDate
            animal.distinguishingFeaturesData = try CoreDataAnimalPayloadCodec.encodeDistinguishingFeatures(
                attributes.distinguishingFeatures
            )
            animal.isArchived = false
            animal.archivedAt = nil
            animal.archiveReason = nil
            animal.herd = herd
            animal.currentPasture = pasture
            animal.sire = sire
            animal.dam = dam
            animal.activeWorkingSession = nil

            let status = AnimalStatusTransitionService.normalizedState(
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
            CoreDataAnimalMutation.applyStatusState(
                status,
                reference: statusReference,
                to: animal
            )

            _ = try CoreDataAnimalMutation.reconcileAggregateTags(
                transaction.tags,
                for: animal,
                herd: herd,
                lookup: self.lookup,
                in: context,
                mutationDate: mutationDate
            )

            return AnimalAggregateEditSnapshot(
                animal: try CoreDataAnimalProjection.detail(animal),
                revision: AnimalAggregateRevision(value: animal.editorRevision)
            )
        }
    }

    func updateAnimal(
        _ transaction: UpdateAnimalAggregateTransaction
    ) throws -> AnimalAggregateEditSnapshot {
        try CoreDataAnimalMutation.validateTagState(transaction.tags)
        let mutationDate = Date()

        return try performWrite { context, herd in
            guard let animal = try self.lookup.herdOwned(
                CDAnimal.self,
                id: transaction.animalID,
                herdID: herd.id,
                in: context
            ) else {
                throw AnimalAggregateTransactionError.aggregateNotFound(
                    animalID: transaction.animalID
                )
            }
            guard animal.editorRevision == transaction.expectedRevision.value else {
                throw AnimalAggregateTransactionError.staleRevision(
                    animalID: transaction.animalID
                )
            }

            let attributesChanged = try CoreDataAnimalMutation.applyAggregateAttributes(
                transaction.attributes,
                to: animal,
                herd: herd,
                lookup: self.lookup,
                in: context,
                mutationDate: mutationDate
            )
            let tagsChanged = try CoreDataAnimalMutation.reconcileAggregateTags(
                transaction.tags,
                for: animal,
                herd: herd,
                lookup: self.lookup,
                in: context,
                mutationDate: mutationDate
            )
            if attributesChanged || tagsChanged {
                CoreDataAnimalMutation.rotateRevision(animal)
            }

            return AnimalAggregateEditSnapshot(
                animal: try CoreDataAnimalProjection.detail(animal),
                revision: AnimalAggregateRevision(value: animal.editorRevision)
            )
        }
    }

    // MARK: - Private

    private nonisolated func reconcileLegacyPrimaryTag(
        animal: CDAnimal,
        number: String,
        colorID: UUID?,
        herd: CDHerd,
        context: NSManagedObjectContext,
        at date: Date
    ) throws {
        let normalizedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = CoreDataAnimalProjection.managedTags(animal)
        let states = tags.map(CoreDataAnimalProjection.tagState)
        let primaryID = AnimalTagService.primaryTag(in: states)?.id
        let primary = primaryID.flatMap { id in tags.first { $0.id == id } }

        if normalizedNumber.isEmpty && tags.isEmpty {
            return
        }

        let target: CDAnimalTag
        if let primary {
            target = primary
        } else {
            target = CDAnimalTag(context: context)
            target.id = try CoreDataAnimalMutation.uniqueID(
                for: CDAnimalTag.self,
                herdID: herd.id,
                lookup: lookup,
                in: context
            )
            target.assignedAt = date
            target.animal = animal
            target.herd = herd
        }

        target.number = normalizedNumber
        target.color = try CoreDataAnimalMutation.resolveTagColor(
            id: colorID,
            herd: herd,
            lookup: lookup,
            in: context
        )
        target.isActive = true
        target.isPrimary = true
        target.removedAt = nil

        for tag in CoreDataAnimalProjection.managedTags(animal)
            where tag.id != target.id && tag.isActive {
            tag.isPrimary = false
        }
    }

    private nonisolated func requiredAnimal(
        id: UUID,
        herdID: UUID,
        context: NSManagedObjectContext
    ) throws -> CDAnimal {
        guard let animal = try lookup.herdOwned(
            CDAnimal.self,
            id: id,
            herdID: herdID,
            in: context
        ) else {
            throw AnimalValidationError.animalNotFound
        }
        return animal
    }

    private func makeReadScope() throws -> (NSManagedObjectContext, UUID) {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        return (contextFactory.makeReadContext(), herdID)
    }

    private func performWrite<Result: Sendable>(
        _ operation: @escaping @Sendable (NSManagedObjectContext, CDHerd) throws -> Result
    ) throws -> Result {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        let context = try contextFactory.makeWriteContext()
        return try context.performAndWait {
            do {
                guard let herd = try lookup.herd(id: herdID, in: context) else {
                    throw HerdRepositoryError.missingHerd
                }

                let result = try operation(context, herd)
                guard context.hasChanges else {
                    return result
                }

                do {
                    try context.save()
                    return result
                } catch {
                    context.rollback()
                    throw CoreDataPersistenceError.saveFailed(
                        description: error.localizedDescription
                    )
                }
            } catch {
                if context.hasChanges {
                    context.rollback()
                }
                throw error
            }
        }
    }
}
