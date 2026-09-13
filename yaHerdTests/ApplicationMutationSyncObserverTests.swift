import XCTest
@testable import yaHerd

@MainActor
final class ApplicationMutationSyncObserverTests: XCTestCase {
    func testForwardsOnlySuccessfulLocalMutations() async {
        let mutationCenter = ApplicationMutationCenter()
        var forwardedReasons: [SharedDataMutationReason] = []
        var observer: ApplicationMutationSyncObserver?

        await withCheckedContinuation { continuation in
            observer = ApplicationMutationSyncObserver(
                mutationStream: mutationCenter
            ) { reason in
                forwardedReasons.append(reason)
                continuation.resume()
            }

            mutationCenter.recordCollaborationStateChange()
            mutationCenter.recordSharedStoreImport()
            mutationCenter.recordPublicIDRepair()
            mutationCenter.recordSuccessfulMutation(reason: .animal)
        }

        XCTAssertEqual(forwardedReasons, [.animal])
        _ = observer
    }
}
