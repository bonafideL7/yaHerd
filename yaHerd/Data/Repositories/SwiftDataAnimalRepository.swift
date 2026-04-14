import Foundation
import SwiftData

struct SwiftDataAnimalRepository: AnimalRepository {
    let context: ModelContext

    func fetchAnimals() throws -> [AnimalSummary] {
        let descriptor = FetchDescriptor<Animal>()
        return try context.fetch(descriptor)
            .map { animal in
                makeSummary(from: animal)
            }
    }

    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? {
        guard let animal = try fetchAnimal(id: id) else { return nil }
        return try makeDetail(from: animal)
    }

    func fetchPastureOptions() throws -> [PastureOption] {
        let descriptor = FetchDescriptor<Pasture>(sortBy: [SortDescriptor(\Pasture.name)])
        return try context.fetch(descriptor).map { pasture in
            PastureOption(id: pasture.publicID, name: pasture.name)
        }
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
            .sorted { lhs, rhs in
                lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
            }
            .map { animal in
                AnimalParentOption(
                    id: animal.publicID,
                    displayTagNumber: animal.displayTagNumber,
                    displayTagColorID: animal.displayTagColorID,
                    sex: animal.sex ?? .female,
                    isArchived: animal.isArchived
                )
            }
    }

    func create(input: AnimalInput) throws -> AnimalDetailSnapshot {
        let pasture = try fetchPasture(id: input.pastureID)
        let sireAnimal = try fetchAnimal(id: input.sireID)
        let damAnimal = try fetchAnimal(id: input.damID)

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

        context.insert(animal)
        if !animal.tagNumber.isEmpty {
            _ = animal.ensurePrimaryTagRecord()
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
        let sireAnimal = try fetchAnimal(id: input.sireID)
        let damAnimal = try fetchAnimal(id: input.damID)

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
        }

        if animal.pasture?.publicID != pasture?.publicID {
            try AnimalMovementService.move(animal, to: pasture, in: context, save: false)
        }

        if animal.status != input.status {
            animal.applyStatus(input.status, effectiveDate: statusEffectiveDate(for: input))
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

        animal.status = input.status
        animal.statusReferenceID = input.statusReferenceID

        switch input.status {
        case .active:
            animal.saleDate = nil
            animal.salePrice = nil
            animal.reasonSold = nil
            animal.deathDate = nil
            animal.causeOfDeath = nil
        case .sold:
            animal.saleDate = input.saleDate
            animal.salePrice = input.salePrice
            animal.reasonSold = input.reasonSold
            animal.deathDate = nil
            animal.causeOfDeath = nil
        case .dead:
            animal.deathDate = input.deathDate
            animal.causeOfDeath = input.causeOfDeath
            animal.saleDate = nil
            animal.salePrice = nil
            animal.reasonSold = nil
        }

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
        try AnimalMovementService.move(animals, to: pasture, in: context)
    }

    func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot {
        guard let animal = try fetchAnimal(id: animalID) else {
            throw AnimalValidationError.animalNotFound
        }
        _ = animal.addTag(number: input.number, colorID: input.colorID, isPrimary: input.isPrimary)
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

    private func makeSummary(from animal: Animal) -> AnimalSummary {
        AnimalSummary(
            id: animal.publicID,
            name: animal.name,
            displayTagNumber: animal.displayTagNumber,
            displayTagColorID: animal.displayTagColorID,
            sex: animal.sex ?? .female,
            birthDate: animal.birthDate,
            status: animal.status,
            isArchived: animal.isArchived,
            pastureID: animal.pasture?.publicID,
            pastureName: animal.pasture?.name,
            location: animal.location
        )
    }

    private func makeDetail(from animal: Animal) throws -> AnimalDetailSnapshot {
        let statusReferenceName = try fetchStatusReferenceName(id: animal.statusReferenceID)
        return AnimalDetailSnapshot(
            id: animal.publicID,
            name: animal.name,
            displayTagNumber: animal.displayTagNumber,
            displayTagColorID: animal.displayTagColorID,
            sex: animal.sex ?? .female,
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
            activeTags: animal.activeTags.map { tag in makeTagSnapshot(from: tag) },
            inactiveTags: animal.inactiveTags.map { tag in makeTagSnapshot(from: tag) },
            location: animal.location
        )
    }

    private func makeTagSnapshot(from tag: AnimalTag) -> AnimalTagSnapshot {
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
        switch input.status {
        case .active:
            return .now
        case .sold:
            return input.saleDate ?? .now
        case .dead:
            return input.deathDate ?? .now
        }
    }
}
