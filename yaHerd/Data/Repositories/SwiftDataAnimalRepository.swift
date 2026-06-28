import Foundation
import SwiftData

struct SwiftDataAnimalRepository: AnimalRepository {
    let context: ModelContext

    func fetchAnimals() throws -> [AnimalSummary] {
        let descriptor = FetchDescriptor<Animal>()
        return try context.fetch(descriptor)
            .map(AnimalMapper.makeSummary)
    }

    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? {
        guard let animal = try fetchAnimal(id: id) else { return nil }
        return try makeDetail(from: animal)
    }

    func fetchTimeline(id: UUID) throws -> [AnimalTimelineEvent] {
        guard let animal = try fetchAnimal(id: id) else { return [] }
        return AnimalMapper.makeTimeline(from: animal)
    }

    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] {
        let descriptor = FetchDescriptor<AnimalStatusReference>(sortBy: [SortDescriptor(\AnimalStatusReference.name)])
        return try context.fetch(descriptor).map { reference in
            AnimalStatusReferenceOption(
                id: reference.id,
                name: reference.name,
                baseStatus: reference.baseStatus
            )
        }
    }

    func fetchParentOptions(excluding excludedAnimalID: UUID?) throws -> [AnimalParentOption] {
        let descriptor = FetchDescriptor<Animal>()
        return try context.fetch(descriptor)
            .filter { animal in
                guard !animal.isSoftDeleted else { return false }
                guard let excludedAnimalID else { return true }
                return animal.publicID != excludedAnimalID
            }
            .map(AnimalMapper.makeParentOption)
            .sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    func fetchOffspringDraftSeed(forDamID damID: UUID) throws -> OffspringDraftSeed? {
        guard let damAnimal = try fetchAnimal(id: damID), !damAnimal.isSoftDeleted else {
            return nil
        }

        let inferredSire = try inferSingleSire(inSamePastureAs: damAnimal, excludingAnimalID: damID)
        return OffspringDraftSeed(
            damID: damAnimal.publicID,
            damDisplayName: AnimalMapper.makeParentOption(from: damAnimal).displayName,
            pastureID: damAnimal.pasture?.publicID,
            pastureName: damAnimal.pasture?.name,
            inferredSireID: inferredSire?.publicID,
            inferredSireDisplayName: inferredSire.map { AnimalMapper.makeParentOption(from: $0).displayName },
            defaultBirthDate: Calendar.current.startOfDay(for: .now)
        )
    }

    func create(input: AnimalInput) throws -> AnimalDetailSnapshot {
        let pasture = try fetchPasture(id: input.pastureID)
        let damAnimal = try fetchAnimal(id: input.damID)
        let sireAnimal = try resolvedSireAnimal(for: input, pasture: pasture, damAnimal: damAnimal)
        try validateAnimalInput(input, animalID: nil, sireAnimal: sireAnimal, damAnimal: damAnimal)

        let animal = Animal(
            name: input.name,
            tagNumber: input.tagNumber,
            tagColorID: input.tagColorID,
            birthDate: input.birthDate,
            status: input.status,
            saleDate: input.saleDate,
            salePrice: input.salePrice,
            reasonSold: input.reasonSold,
            deathDate: input.deathDate,
            causeOfDeath: input.causeOfDeath,
            statusReferenceID: input.statusReferenceID,
            sireAnimal: sireAnimal,
            damAnimal: damAnimal,
            pasture: pasture,
            sex: input.sex,
            distinguishingFeatures: input.distinguishingFeatures
        )

        try ensureUniqueAnimalPublicID(animal)
        context.insert(animal)
        if !animal.tagNumber.isEmpty {
            let tag = animal.ensurePrimaryTagRecord()
            try ensureUniqueAnimalTagPublicID(tag)
        }
        try context.save()
        return try makeDetail(from: animal)
    }

    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot {
        guard let animal = try fetchAnimal(id: id) else {
            throw AnimalValidationError.animalNotFound
        }

        let oldStatus = animal.status
        let oldStatusReferenceID = animal.statusReferenceID
        let pasture = try fetchPasture(id: input.pastureID)
        let damAnimal = try fetchAnimal(id: input.damID)
        let sireAnimal = try resolvedSireAnimal(for: input, pasture: pasture, damAnimal: damAnimal)
        try validateAnimalInput(input, animalID: id, sireAnimal: sireAnimal, damAnimal: damAnimal)

        animal.name = input.name
        animal.sex = input.sex
        animal.birthDate = input.birthDate
        animal.sireAnimal = sireAnimal
        animal.damAnimal = damAnimal
        animal.distinguishingFeatures = input.distinguishingFeatures

        if input.tagNumber.isEmpty, animal.tags.isEmpty {
            animal.tagNumber = ""
            animal.tagColorID = input.tagColorID
        } else {
            animal.updatePrimaryTag(number: input.tagNumber, colorID: input.tagColorID)
            try ensureUniqueAnimalTagPublicIDs(for: animal)
        }

        if animal.pasture?.publicID != pasture?.publicID {
            try AnimalMovementStore.move(animal, to: pasture, in: context, save: false)
        }

        if animal.status != input.status {
            let record = StatusRecord(
                date: .now,
                oldStatus: oldStatus,
                newStatus: input.status,
                oldStatusReferenceID: oldStatusReferenceID,
                newStatusReferenceID: input.statusReferenceID,
                animal: animal
            )
            context.insert(record)
        }

        animal.applyStatusState(
            AnimalStatusTransitionService.normalizedState(
                status: input.status,
                saleDate: input.saleDate,
                salePrice: input.salePrice,
                reasonSold: input.reasonSold,
                deathDate: input.deathDate,
                causeOfDeath: input.causeOfDeath,
                statusReferenceID: input.statusReferenceID,
                effectiveDate: statusEffectiveDate(for: input)
            )
        )

        try context.save()
        return try makeDetail(from: animal)
    }

    func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<Animal>()
        for animal in try context.fetch(descriptor) where idSet.contains(animal.publicID) {
            context.delete(animal)
        }
        try context.save()
    }

    func archive(ids: [UUID]) throws {
        try updateArchiveState(ids: ids, isArchived: true)
    }

    func restore(ids: [UUID]) throws {
        try updateArchiveState(ids: ids, isArchived: false)
    }

    func move(ids: [UUID], toPastureID: UUID?) throws {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let pasture = try fetchPasture(id: toPastureID)
        let descriptor = FetchDescriptor<Animal>()
        let animals = try context.fetch(descriptor).filter { idSet.contains($0.publicID) }
        try AnimalMovementStore.move(animals, to: pasture, in: context)
    }

    func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot {
        guard let animal = try fetchAnimal(id: animalID) else {
            throw AnimalValidationError.animalNotFound
        }
        let tag = animal.addTag(number: input.number, colorID: input.colorID, isPrimary: input.isPrimary)
        try ensureUniqueAnimalTagPublicID(tag)
        try context.save()
        return try makeDetail(from: animal)
    }

    func updateTag(animalID: UUID, tagID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot {
        guard let animal = try fetchAnimal(id: animalID) else {
            throw AnimalValidationError.animalNotFound
        }
        guard let tag = animal.tags.first(where: { $0.publicID == tagID }) else {
            throw AnimalValidationError.animalTagNotFound
        }
        animal.updateTag(tag, number: input.number, colorID: input.colorID, isPrimary: input.isPrimary)
        try ensureUniqueAnimalTagPublicID(tag)
        try context.save()
        return try makeDetail(from: animal)
    }

    func promoteTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot {
        guard let animal = try fetchAnimal(id: animalID) else {
            throw AnimalValidationError.animalNotFound
        }
        guard let tag = animal.tags.first(where: { $0.publicID == tagID }) else {
            throw AnimalValidationError.animalTagNotFound
        }
        animal.promoteTagToPrimary(tag)
        try context.save()
        return try makeDetail(from: animal)
    }

    func retireTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot {
        guard let animal = try fetchAnimal(id: animalID) else {
            throw AnimalValidationError.animalNotFound
        }
        guard let tag = animal.tags.first(where: { $0.publicID == tagID }) else {
            throw AnimalValidationError.animalTagNotFound
        }
        animal.retireTag(tag)
        try context.save()
        return try makeDetail(from: animal)
    }


    func addHealthRecord(animalID: UUID, input: HealthRecordInput) throws -> AnimalDetailSnapshot {
        guard let animal = try fetchAnimal(id: animalID) else {
            throw AnimalValidationError.animalNotFound
        }
        let record = HealthRecord(date: input.date, treatment: input.treatment, notes: input.notes, animal: animal)
        context.insert(record)
        try context.save()
        return try makeDetail(from: animal)
    }

    func addPregnancyCheck(animalID: UUID, input: PregnancyCheckInput) throws -> AnimalDetailSnapshot {
        guard let animal = try fetchAnimal(id: animalID) else {
            throw AnimalValidationError.animalNotFound
        }
        let check = PregnancyCheck(
            date: input.date,
            result: input.result,
            technician: input.technician,
            estimatedDaysPregnant: input.estimatedDaysPregnant,
            dueDate: input.dueDate,
            sireAnimal: try fetchAnimal(id: input.sireAnimalID),
            workingSession: nil,
            animal: animal
        )
        context.insert(check)
        try context.save()
        return try makeDetail(from: animal)
    }

    private func ensureUniqueAnimalPublicID(_ animal: Animal) throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<Animal>()).map(\.publicID))
        while existingIDs.contains(animal.publicID) {
            animal.publicID = UUID()
        }
    }

    private func ensureUniqueAnimalTagPublicIDs(for animal: Animal) throws {
        for tag in animal.tags {
            try ensureUniqueAnimalTagPublicID(tag)
        }
    }

    private func ensureUniqueAnimalTagPublicID(_ tag: AnimalTag) throws {
        let existingTags = try context.fetch(FetchDescriptor<AnimalTag>())
        let existingIDs = Set(existingTags.filter { $0 !== tag }.map(\.publicID))
        while existingIDs.contains(tag.publicID) {
            tag.publicID = UUID()
        }
    }

    private func updateArchiveState(ids: [UUID], isArchived: Bool) throws {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<Animal>()
        for animal in try context.fetch(descriptor) where idSet.contains(animal.publicID) {
            if isArchived {
                animal.archive()
            } else {
                animal.restoreArchivedRecord()
            }
        }
        try context.save()
    }

    private func fetchAnimal(id: UUID?) throws -> Animal? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Animal>(
            predicate: #Predicate<Animal> { animal in
                animal.publicID == id
            }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchPasture(id: UUID?) throws -> Pasture? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Pasture>(
            predicate: #Predicate<Pasture> { pasture in
                pasture.publicID == id
            }
        )
        return try context.fetch(descriptor).first
    }


    private func validateAnimalInput(_ input: AnimalInput, animalID: UUID?, sireAnimal: Animal?, damAnimal: Animal?) throws {
        try ValidationService.validateAnimal(
            ValidationService.AnimalValidationRules(
                birthDate: input.birthDate,
                status: input.status,
                saleDate: input.saleDate,
                deathDate: input.deathDate,
                animalID: animalID,
                sireID: input.sireID,
                sireSex: sireAnimal?.sex,
                damID: input.damID,
                damSex: damAnimal?.sex
            )
        )
    }

    private func makeDetail(from animal: Animal) throws -> AnimalDetailSnapshot {
        let statusReferenceName = try fetchStatusReferenceName(id: animal.statusReferenceID)
        return AnimalMapper.makeDetail(from: animal, statusReferenceName: statusReferenceName)
    }

    private func fetchStatusReferenceName(id: UUID?) throws -> String? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<AnimalStatusReference>(
            predicate: #Predicate<AnimalStatusReference> { reference in
                reference.id == id
            }
        )
        return try context.fetch(descriptor).first?.name
    }

    private func statusEffectiveDate(for input: AnimalInput) -> Date {
        AnimalStatusTransitionService.effectiveDate(
            for: input.status,
            saleDate: input.saleDate,
            deathDate: input.deathDate
        )
    }
}


private extension SwiftDataAnimalRepository {
    func resolvedSireAnimal(for input: AnimalInput, pasture: Pasture?, damAnimal: Animal?) throws -> Animal? {
        if let explicitSire = try fetchAnimal(id: input.sireID) {
            return explicitSire
        }

        guard input.damID != nil else { return nil }
        let pastureToUse = pasture ?? damAnimal?.pasture
        guard let pastureToUse else { return nil }
        return try inferSingleSire(inPastureID: pastureToUse.publicID, excludingAnimalID: input.damID)
    }

    func inferSingleSire(inSamePastureAs animal: Animal, excludingAnimalID: UUID?) throws -> Animal? {
        guard let pastureID = animal.pasture?.publicID else { return nil }
        return try inferSingleSire(inPastureID: pastureID, excludingAnimalID: excludingAnimalID)
    }

    func inferSingleSire(inPastureID pastureID: UUID, excludingAnimalID: UUID?) throws -> Animal? {
        let descriptor = FetchDescriptor<Animal>()
        let matches = try context.fetch(descriptor)
            .filter { animal in
                guard !animal.isSoftDeleted else { return false }
                guard animal.status == .active else { return false }
                guard animal.sex == .male else { return false }
                guard animal.animalType == .bull else { return false }
                guard animal.pasture?.publicID == pastureID else { return false }
                guard animal.publicID != excludingAnimalID else { return false }
                return true
            }

        return matches.count == 1 ? matches[0] : nil
    }
}
