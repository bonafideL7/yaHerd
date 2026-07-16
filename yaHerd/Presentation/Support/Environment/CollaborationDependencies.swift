import SwiftUI

nonisolated struct CollaborationDependencies {
    let herdRepository: (any HerdRepository)?
    let sharingRepository: (any HerdSharingRepository)?
    let invitationCoordinator: CloudKitShareInvitationCoordinator?
    let shareAdapter: CloudKitShareAdapter?
    let syncCoordinator: HerdSharingSyncCoordinator?
    let writePolicy: HerdCollaborationWritePolicy?
    let conflictReviewStore: HerdSharingConflictReviewStore?
    let diagnosticsRepository: (any SyncDiagnosticsRepository)?

    nonisolated init() {
        self.herdRepository = nil
        self.sharingRepository = nil
        self.invitationCoordinator = nil
        self.shareAdapter = nil
        self.syncCoordinator = nil
        self.writePolicy = nil
        self.conflictReviewStore = nil
        self.diagnosticsRepository = nil
    }

    @MainActor
    init(
        herdRepository: any HerdRepository,
        sharingRepository: any HerdSharingRepository,
        invitationCoordinator: CloudKitShareInvitationCoordinator,
        shareAdapter: CloudKitShareAdapter,
        syncCoordinator: HerdSharingSyncCoordinator,
        writePolicy: HerdCollaborationWritePolicy,
        conflictReviewStore: HerdSharingConflictReviewStore,
        diagnosticsRepository: any SyncDiagnosticsRepository
    ) {
        self.herdRepository = herdRepository
        self.sharingRepository = sharingRepository
        self.invitationCoordinator = invitationCoordinator
        self.shareAdapter = shareAdapter
        self.syncCoordinator = syncCoordinator
        self.writePolicy = writePolicy
        self.conflictReviewStore = conflictReviewStore
        self.diagnosticsRepository = diagnosticsRepository
    }
}

private struct CollaborationDependenciesKey: EnvironmentKey {
    static let defaultValue = CollaborationDependencies()
}

extension EnvironmentValues {
    var collaborationDependencies: CollaborationDependencies {
        get { self[CollaborationDependenciesKey.self] }
        set { self[CollaborationDependenciesKey.self] = newValue }
    }
}
