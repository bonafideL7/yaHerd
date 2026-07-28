import Foundation

@MainActor
extension SyncRequestingWorkingRepository {
    func startSession(input: WorkingSessionStartInput) throws -> UUID {
        try writePolicy.validateCanWrite(reason: .working)
        let sessionID = try base.startSession(input: input)
        mutationRecorder.recordSuccessfulMutation(reason: .working)
        return sessionID
    }
}
