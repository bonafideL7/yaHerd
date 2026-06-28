import Foundation
import SwiftData

struct SwiftDataPublicIDUniquenessStore {
    let context: ModelContext

    func ensureUniqueSessionPublicID(_ session: WorkingSession) throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<WorkingSession>()).map(\.publicID))
        while existingIDs.contains(session.publicID) {
            session.publicID = UUID()
        }
    }

    func ensureUniqueQueueItemPublicID(_ item: WorkingQueueItem) throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<WorkingQueueItem>()).map(\.publicID))
        while existingIDs.contains(item.publicID) {
            item.publicID = UUID()
        }
    }

    func ensureUniqueTemplatePublicID(_ template: WorkingProtocolTemplate) throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<WorkingProtocolTemplate>()).map(\.publicID))
        while existingIDs.contains(template.publicID) {
            template.publicID = UUID()
        }
    }
}
