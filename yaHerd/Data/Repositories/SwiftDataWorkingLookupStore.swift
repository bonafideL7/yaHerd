import Foundation
import SwiftData

struct SwiftDataWorkingLookupStore {
    let context: ModelContext

    func fetchSession(id: UUID) throws -> WorkingSession {
        var descriptor = FetchDescriptor<WorkingSession>(predicate: #Predicate<WorkingSession> { session in
            session.publicID == id
        })
        descriptor.fetchLimit = 1
        guard let session = try context.fetch(descriptor).first else {
            throw WorkingRepositoryError.sessionNotFound
        }
        return session
    }

    func fetchQueueItem(id: UUID, sessionID: UUID) throws -> WorkingQueueItem {
        var descriptor = FetchDescriptor<WorkingQueueItem>(predicate: #Predicate<WorkingQueueItem> { item in
            item.publicID == id && item.session?.publicID == sessionID
        })
        descriptor.fetchLimit = 1
        guard let item = try context.fetch(descriptor).first else {
            throw WorkingRepositoryError.queueItemNotFound
        }
        return item
    }

    func fetchTemplate(id: UUID) throws -> WorkingProtocolTemplate {
        var descriptor = FetchDescriptor<WorkingProtocolTemplate>(predicate: #Predicate<WorkingProtocolTemplate> { template in
            template.publicID == id
        })
        descriptor.fetchLimit = 1
        guard let template = try context.fetch(descriptor).first else {
            throw WorkingRepositoryError.templateNotFound
        }
        return template
    }

    func templateNameExists(_ name: String, excluding id: UUID?) throws -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor: FetchDescriptor<WorkingProtocolTemplate>
        if let id {
            descriptor = FetchDescriptor<WorkingProtocolTemplate>(
                predicate: #Predicate<WorkingProtocolTemplate> { template in
                    template.publicID != id && template.name.localizedStandardContains(normalizedName)
                }
            )
        } else {
            descriptor = FetchDescriptor<WorkingProtocolTemplate>(
                predicate: #Predicate<WorkingProtocolTemplate> { template in
                    template.name.localizedStandardContains(normalizedName)
                }
            )
        }

        return try context.fetch(descriptor).contains { template in
            template.name.caseInsensitiveCompare(normalizedName) == .orderedSame
        }
    }

    func fetchAnimals(ids: [UUID]) throws -> [Animal] {
        let uniqueIDs = ids.reduce(into: [UUID]()) { result, id in
            guard !result.contains(id) else { return }
            result.append(id)
        }
        guard !uniqueIDs.isEmpty else { return [] }

        return try PerformanceLog.measure("SwiftDataWorkingLookupStore.fetchAnimalsByIDs") {
            let descriptor = FetchDescriptor<Animal>(
                predicate: #Predicate<Animal> { animal in
                    uniqueIDs.contains(animal.publicID)
                }
            )
            let fetchedAnimals = try context.fetch(descriptor)
            var animalsByID: [UUID: Animal] = [:]
            for animal in fetchedAnimals {
                animalsByID[animal.publicID] = animal
            }
            return uniqueIDs.compactMap { animalsByID[$0] }
        }
    }

    func fetchTemplates(ids: [UUID]) throws -> [WorkingProtocolTemplate] {
        let uniqueIDs = ids.reduce(into: [UUID]()) { result, id in
            guard !result.contains(id) else { return }
            result.append(id)
        }
        guard !uniqueIDs.isEmpty else { return [] }

        return try PerformanceLog.measure("SwiftDataWorkingLookupStore.fetchTemplatesByIDs") {
            let descriptor = FetchDescriptor<WorkingProtocolTemplate>(
                predicate: #Predicate<WorkingProtocolTemplate> { template in
                    uniqueIDs.contains(template.publicID)
                }
            )
            let fetchedTemplates = try context.fetch(descriptor)
            var templatesByID: [UUID: WorkingProtocolTemplate] = [:]
            for template in fetchedTemplates {
                templatesByID[template.publicID] = template
            }

            guard templatesByID.count == uniqueIDs.count else {
                throw WorkingRepositoryError.templateNotFound
            }

            return uniqueIDs.compactMap { templatesByID[$0] }
        }
    }

    func fetchPasture(id: UUID?) throws -> Pasture? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<Pasture>(predicate: #Predicate<Pasture> { pasture in
            pasture.publicID == id
        })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchTreatmentRecords(session: WorkingSession, animal: Animal) throws -> [WorkingTreatmentRecord] {
        let sessionID = session.publicID
        let animalID = animal.publicID
        let descriptor = FetchDescriptor<WorkingTreatmentRecord>(
            predicate: #Predicate<WorkingTreatmentRecord> { record in
                record.session?.publicID == sessionID && record.animal?.publicID == animalID
            }
        )
        return try context.fetch(descriptor)
    }

    func fetchPregnancyChecks(session: WorkingSession, animal: Animal) throws -> [PregnancyCheck] {
        let sessionID = session.publicID
        let animalID = animal.publicID
        let descriptor = FetchDescriptor<PregnancyCheck>(
            predicate: #Predicate<PregnancyCheck> { check in
                check.workingSession?.publicID == sessionID && check.animal?.publicID == animalID
            }
        )
        return try context.fetch(descriptor)
    }

    func fetchHealthRecords(session: WorkingSession, animal: Animal) throws -> [HealthRecord] {
        let sessionID = session.publicID
        let animalID = animal.publicID
        let descriptor = FetchDescriptor<HealthRecord>(
            predicate: #Predicate<HealthRecord> { record in
                record.workingSession?.publicID == sessionID && record.animal?.publicID == animalID
            }
        )
        return try context.fetch(descriptor)
    }
}
