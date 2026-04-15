import Foundation

struct LoadWorkingQueueItemEditorUseCase {
    let repository: any WorkingRepository

    func execute(sessionID: UUID, queueItemID: UUID) throws -> WorkingQueueItemEditorSnapshot? {
        try repository.fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID)
    }
}
