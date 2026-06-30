import Foundation
import SwiftData

struct SwiftDataPublicIDUniquenessStore {
    let context: ModelContext

    func ensureUniqueSessionPublicID(_ session: WorkingSession) throws {
        while try workingSessionPublicIDExists(session.publicID, excluding: session) {
            session.publicID = UUID()
        }
    }

    func ensureUniqueQueueItemPublicID(_ item: WorkingQueueItem) throws {
        while try workingQueueItemPublicIDExists(item.publicID, excluding: item) {
            item.publicID = UUID()
        }
    }

    func ensureUniqueTemplatePublicID(_ template: WorkingProtocolTemplate) throws {
        while try workingProtocolTemplatePublicIDExists(template.publicID, excluding: template) {
            template.publicID = UUID()
        }
    }

    private func workingSessionPublicIDExists(_ id: UUID, excluding session: WorkingSession) throws -> Bool {
        let descriptor = FetchDescriptor<WorkingSession>(
            predicate: #Predicate<WorkingSession> { existing in
                existing.publicID == id
            }
        )
        return try context.fetch(descriptor).contains { $0 !== session }
    }

    private func workingQueueItemPublicIDExists(_ id: UUID, excluding item: WorkingQueueItem) throws -> Bool {
        let descriptor = FetchDescriptor<WorkingQueueItem>(
            predicate: #Predicate<WorkingQueueItem> { existing in
                existing.publicID == id
            }
        )
        return try context.fetch(descriptor).contains { $0 !== item }
    }

    private func workingProtocolTemplatePublicIDExists(_ id: UUID, excluding template: WorkingProtocolTemplate) throws -> Bool {
        let descriptor = FetchDescriptor<WorkingProtocolTemplate>(
            predicate: #Predicate<WorkingProtocolTemplate> { existing in
                existing.publicID == id
            }
        )
        return try context.fetch(descriptor).contains { $0 !== template }
    }
}
