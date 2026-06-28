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
            item.publicID == id
        })
        guard let item = try context.fetch(descriptor).first,
              item.session?.publicID == sessionID else {
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
        let descriptor = FetchDescriptor<WorkingProtocolTemplate>()
        return try context.fetch(descriptor).contains { template in
            if let id, template.publicID == id {
                return false
            }
            return template.name.caseInsensitiveCompare(normalizedName) == .orderedSame
        }
    }

    func fetchAnimals(ids: [UUID]) throws -> [Animal] {
        guard !ids.isEmpty else { return [] }
        let all = try context.fetch(FetchDescriptor<Animal>())
        let animalsByID = Dictionary(uniqueKeysWithValues: all.map { ($0.publicID, $0) })
        return ids.compactMap { animalsByID[$0] }
    }

    func fetchPasture(id: UUID?) throws -> Pasture? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Pasture>(predicate: #Predicate<Pasture> { pasture in
            pasture.publicID == id
        })
        return try context.fetch(descriptor).first
    }

    func fetchTreatmentRecords(session: WorkingSession, animal: Animal) throws -> [WorkingTreatmentRecord] {
        let sid = session.persistentModelID
        let aid = animal.persistentModelID
        return try context.fetch(FetchDescriptor<WorkingTreatmentRecord>()).filter {
            $0.session?.persistentModelID == sid && $0.animal?.persistentModelID == aid
        }
    }

    func fetchPregnancyChecks(session: WorkingSession, animal: Animal) throws -> [PregnancyCheck] {
        let sid = session.persistentModelID
        let aid = animal.persistentModelID
        return try context.fetch(FetchDescriptor<PregnancyCheck>()).filter {
            $0.workingSession?.persistentModelID == sid && $0.animal?.persistentModelID == aid
        }
    }

    func fetchHealthRecords(session: WorkingSession, animal: Animal) throws -> [HealthRecord] {
        let sid = session.persistentModelID
        let aid = animal.persistentModelID
        return try context.fetch(FetchDescriptor<HealthRecord>()).filter {
            $0.workingSession?.persistentModelID == sid && $0.animal?.persistentModelID == aid
        }
    }
}
