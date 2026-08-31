import Foundation

@MainActor
extension SyncRequestingFieldCheckRepository: ApplicationMutationStreamProviding {
    var applicationMutationStream: any ApplicationMutationStreaming {
        guard let provider = mutationRecorder as? any ApplicationMutationStreamProviding else {
            return InactiveApplicationMutationStream()
        }
        return provider.applicationMutationStream
    }
}
