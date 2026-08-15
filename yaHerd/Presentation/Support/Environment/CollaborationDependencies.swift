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
    let publicIDRepairService: (any PublicIDRepairService)?
    let settingsSynchronizer: (any AppSettingsSyncing)?

    nonisolated init() {
        self.herdRepository = nil
        self.sharingRepository = nil
        self.invitationCoordinator = nil
        self.shareAdapter = nil
        self.syncCoordinator = nil
        self.writePolicy = nil
        self.conflictReviewStore = nil
        self.diagnosticsRepository = nil
        self.publicIDRepairService = nil
        self.settingsSynchronizer = nil
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
        diagnosticsRepository: any SyncDiagnosticsRepository,
        settingsSynchronizer: any AppSettingsSyncing
    ) {
        self.herdRepository = herdRepository
        self.sharingRepository = sharingRepository
        self.invitationCoordinator = invitationCoordinator
        self.shareAdapter = shareAdapter
        self.syncCoordinator = syncCoordinator
        self.writePolicy = writePolicy
        self.conflictReviewStore = conflictReviewStore
        self.diagnosticsRepository = diagnosticsRepository
        self.publicIDRepairService = diagnosticsRepository.publicIDRepairService
        self.settingsSynchronizer = settingsSynchronizer
    }
}

private struct CollaborationDependenciesKey: EnvironmentKey {
    static var defaultValue: CollaborationDependencies {
        CollaborationDependencies()
    }
}

extension EnvironmentValues {
    var collaborationDependencies: CollaborationDependencies {
        get { self[CollaborationDependenciesKey.self] }
        set { self[CollaborationDependenciesKey.self] = newValue }
    }
}
