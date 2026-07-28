import Foundation

@MainActor
extension SyncRequestingWorkingRepository {
    func reopenSession(id: UUID) throws {
        try writePolicy.validateCanWrite(reason: .working)
        try base.reopenSession(id: id)
        mutationRecorder.recordSuccessfulMutation(reason: .working)
    }
}
