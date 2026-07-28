import Foundation

@MainActor
extension SyncRequestingWorkingRepository {
    func replacePrimaryTag(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingTagReplacementInput
    ) throws -> WorkingQueueItemEditorSnapshot {
        try writePolicy.validateCanWrite(reason: .working)
        let snapshot = try base.replacePrimaryTag(
            forQueueItemID: queueItemID,
            inSessionID: sessionID,
            input: input
        )
        mutationRecorder.recordSuccessfulMutation(reason: .working)
        return snapshot
    }
}
