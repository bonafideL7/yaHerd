import Foundation

struct LoadWorkingQueueItemEditorUseCase {
    let repository: any WorkingQueueItemEditorReader

    func execute(sessionID: UUID, queueItemID: UUID) throws -> WorkingQueueItemEditorSnapshot? {
        try repository.fetchQueueItemEditor(sessionID: sessionID, queueItemID: queueItemID)
    }
}
