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
    private let transactionExecutor: CoreDataTransactionExecutor
    private nonisolated let lookup: CoreDataLookup

    init(
        selection: any CurrentHerdSelectionReading,
        contextFactory: CoreDataContextFactory,
        transactionExecutor: CoreDataTransactionExecutor,
        lookup: CoreDataLookup
    ) {
        self.selection = selection
        self.contextFactory = contextFactory
        self.transactionExecutor = transactionExecutor
        self.lookup = lookup
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            selection: selection,
            contextFactory: assembly.contextFactory,
            transactionExecutor: assembly.transactionExecutor,
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
                .map(CoreDataAnimalProjection.summary)
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
            return CoreDataAnimalProjection.detail(animal)
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
            return CoreDataAnimalProjection.timeline(animal)
        }
    }

    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            let request = NSFetchRequest<CDAnimalStatusReference>(
                entityName: CDAnimalStatusReference.coreDataEntityName
            )
            request.predicate = NSPredicate(format: "herd == %@", herd)
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            return try context.fetch(request).map {
                AnimalStatusReferenceOption(
                    id: $0.id,
                    name: $0.name,
                    baseStatus: AnimalStatus(rawValue: $0.baseStatusRawValue) ?? .active
                )
            }
        }
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
                .map(CoreDataAnimalProjection.parentOption)
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
                damDisplayName: CoreDataAnimalProjection.parentOption(dam).displayName,
                pastureID: dam.currentPasture?.id,
                pastureName: dam.currentPasture?.name,
                inferredSireID: inferredSire?.id,
                inferredSireDisplayName: inferredSire.map {
                    CoreDataAnimalProjection.parentOption($0).displayName
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
                animal: CoreDataAnimalProjection.detail(animal),
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
                id: input.sireAnimalID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            let sire = explicitSire ?? (dam == nil ? nil : try CoreDataAnimalMutation.inferSingleSire(
                pastureID: pasture?.id,
                excluding: nil,
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
            animal.distinguishingFeaturesData = try JSONEncoder().encode(
                input.distinguishingFeatures.normalizedDistinguishingFeatureOrder
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

            return CoreDataAnimalProjection.detail(animal)
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

            let beforeAttributes = CoreDataAnimalMutation.aggregateAttributes(animal)
            let beforeTags = CoreDataAnimalMutation.aggregateTagStates(animal)
            let oldStatus = AnimalStatus(rawValue: animal.statusRawValue) ?? .active
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
                id: input.sireAnimalID,
                herdID: herd.id,
                lookup: self.lookup,
                in: context
            )
            let sire = explicitSire ?? (dam == nil ? nil : try CoreDataAnimalMutation.inferSingleSire(
                pastureID: pasture?.id,
                excluding: id,
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
            animal.distinguishingFeaturesData = try JSONEncoder().encode(
                input.distinguishingFeatures.normalizedDistinguishingFeatureOrder
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

            if beforeAttributes != CoreDataAnimalMutation.aggregateAttributes(animal)
                || beforeTags != CoreDataAnimalMutation.aggregateTagStates(animal) {
                CoreDataAnimalMutation.rotateRevision(animal)
            }

            return CoreDataAnimalProjection.detail(animal)
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
            if shouldBePrimary {
                for tag in tags where tag.isActive {
                    tag.isPrimary = false
                }
            }

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
            CoreDataAnimalMutation.rotateRevision(animal)
            return CoreDataAnimalProjection.detail(animal)
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
                    for existing in tags where existing.isActive {
                        existing.isPrimary = existing.id == tag.id
                    }
                } else {
                    let otherActive = tags.filter { $0.isActive && $0.id != tag.id }
                    if otherActive.isEmpty {
                        tag.isPrimary = true
                    } else {
                        tag.isPrimary = false
                        let states = tags.map(CoreDataAnimalProjection.tagState)
                        if AnimalTagService.primaryTag(in: states) == nil,
                           let replacementID = AnimalTagService.activeTags(states).first?.id,
                           let replacement = tags.first(where: { $0.id == replacementID }) {
                            replacement.isPrimary = true
                        }
                    }
                }
            } else {
                tag.isPrimary = false
            }

            if before != CoreDataAnimalMutation.aggregateTagStates(animal) {
                CoreDataAnimalMutation.rotateRevision(animal)
            }
            return CoreDataAnimalProjection.detail(animal)
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
            for existing in CoreDataAnimalProjection.managedTags(animal) where existing.isActive {
                existing.isPrimary = existing.id == tag.id
            }
            tag.isActive = true
            tag.isPrimary = true
            tag.removedAt = nil

            if before != CoreDataAnimalMutation.aggregateTagStates(animal) {
                CoreDataAnimalMutation.rotateRevision(animal)
            }
            return CoreDataAnimalProjection.detail(animal)
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
                replacement.isPrimary = true
                replacement.removedAt = nil
            }

            if before != CoreDataAnimalMutation.aggregateTagStates(animal) {
                CoreDataAnimalMutation.rotateRevision(animal)
            }
            return CoreDataAnimalProjection.detail(animal)
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
            return CoreDataAnimalProjection.detail(animal)
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
                id: input.sireID,
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
            return CoreDataAnimalProjection.detail(animal)
        }
    }

    // MARK: - Atomic aggregate transaction boundary

    func createAnimal(
        _ transaction: CreateAnimalAggregateTransaction
    ) async throws -> AnimalAggregateEditSnapshot {
        try await createAnimal(transaction, beforeSave: nil)
    }

    func createAnimal(
        _ transaction: CreateAnimalAggregateTransaction,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws -> AnimalAggregateEditSnapshot {
        try CoreDataAnimalMutation.validateTagState(transaction.tags)
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

        let lookup = self.lookup
        let mutationDate = Date()
        _ = try await transactionExecutor.performWrite(beforeSave: beforeSave) { context in
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            if try lookup.herdOwned(
                CDAnimal.self,
                id: transaction.animalID,
                herdID: herdID,
                in: context
            ) != nil {
                throw CoreDataPersistenceError.duplicateApplicationID(
                    entity: CDAnimal.coreDataEntityName,
                    id: transaction.animalID,
                    herdID: herdID
                )
            }

            let attributes = transaction.attributes
            let pasture = try CoreDataAnimalMutation.resolvePasture(
                id: attributes.pastureID,
                herdID: herdID,
                lookup: lookup,
                in: context
            )
            let sire = try CoreDataAnimalMutation.resolveAnimal(
                id: attributes.sireID,
                herdID: herdID,
                lookup: lookup,
                in: context
            )
            let dam = try CoreDataAnimalMutation.resolveAnimal(
                id: attributes.damID,
                herdID: herdID,
                lookup: lookup,
                in: context
            )
            let statusReference = try CoreDataAnimalMutation.resolveStatusReference(
                id: attributes.statusReferenceID,
                herdID: herdID,
                lookup: lookup,
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
            animal.distinguishingFeaturesData = try JSONEncoder().encode(
                attributes.distinguishingFeatures.normalizedDistinguishingFeatureOrder
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
                lookup: lookup,
                in: context,
                mutationDate: mutationDate
            )
            return animal.editorRevision
        }

        guard let created = try fetchAnimalAggregateForEditing(id: transaction.animalID) else {
            throw AnimalAggregateTransactionError.aggregateNotFound(
                animalID: transaction.animalID
            )
        }
        return created
    }

    func updateAnimal(
        _ transaction: UpdateAnimalAggregateTransaction
    ) async throws -> AnimalAggregateEditSnapshot {
        try await updateAnimal(transaction, beforeSave: nil)
    }

    func updateAnimal(
        _ transaction: UpdateAnimalAggregateTransaction,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws -> AnimalAggregateEditSnapshot {
        try CoreDataAnimalMutation.validateTagState(transaction.tags)
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

        let lookup = self.lookup
        let mutationDate = Date()
        _ = try await transactionExecutor.performWrite(beforeSave: beforeSave) { context in
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            guard let animal = try lookup.herdOwned(
                CDAnimal.self,
                id: transaction.animalID,
                herdID: herdID,
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
                lookup: lookup,
                in: context,
                mutationDate: mutationDate
            )
            let tagsChanged = try CoreDataAnimalMutation.reconcileAggregateTags(
                transaction.tags,
                for: animal,
                herd: herd,
                lookup: lookup,
                in: context,
                mutationDate: mutationDate
            )
            if attributesChanged || tagsChanged {
                CoreDataAnimalMutation.rotateRevision(animal)
            }
            return animal.editorRevision
        }

        guard let updated = try fetchAnimalAggregateForEditing(id: transaction.animalID) else {
            throw AnimalAggregateTransactionError.aggregateNotFound(
                animalID: transaction.animalID
            )
        }
        return updated
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
                if context.hasChanges {
                    do {
                        try context.save()
                    } catch {
                        context.rollback()
                        throw CoreDataPersistenceError.saveFailed(
                            description: error.localizedDescription
                        )
                    }
                }
                return result
            } catch {
                if context.hasChanges {
                    context.rollback()
                }
                throw error
            }
        }
    }
}
