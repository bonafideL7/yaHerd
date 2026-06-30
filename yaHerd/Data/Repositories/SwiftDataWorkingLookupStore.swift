import Foundation
import SwiftData

struct SwiftDataWorkingLookupStore {
    let context: ModelContext

    func fetchSession(id: UUID) throws -> WorkingSession {
        let descriptor = FetchDescriptor<WorkingSession>(predicate: #Predicate<WorkingSession> { session in
            session.publicID == id
        })
        guard let session = try context.fetch(descriptor).first else {
            throw WorkingRepositoryError.sessionNotFound
        }
        return session
    }

    func fetchQueueItem(id: UUID, sessionID: UUID) throws -> WorkingQueueItem {
        let descriptor = FetchDescriptor<WorkingQueueItem>(predicate: #Predicate<WorkingQueueItem> { item in
            item.publicID == id && item.session?.publicID == sessionID
        })
        guard let item = try context.fetch(descriptor).first else {
            throw WorkingRepositoryError.queueItemNotFound
        }
        return item
    }

    func fetchTemplate(id: UUID) throws -> WorkingProtocolTemplate {
        let descriptor = FetchDescriptor<WorkingProtocolTemplate>(predicate: #Predicate<WorkingProtocolTemplate> { template in
            template.publicID == id
        })
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
        var animals: [Animal] = []
        var seenIDs = Set<UUID>()

        for id in ids {
            guard seenIDs.insert(id).inserted else { continue }
            let descriptor = FetchDescriptor<Animal>(predicate: #Predicate<Animal> { animal in
                animal.publicID == id
            })
            if let animal = try context.fetch(descriptor).first {
                animals.append(animal)
            }
        }

        return animals
    }

    func fetchPasture(id: UUID?) throws -> Pasture? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Pasture>(predicate: #Predicate<Pasture> { pasture in
            pasture.publicID == id
        })
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
