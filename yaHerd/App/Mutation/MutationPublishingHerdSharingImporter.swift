import Foundation

/// Publishes application invalidation at the SwiftData shared-import commit boundary.
/// A committed import can still fail during reconciliation, so the importer must publish for both
/// a successful application and `HerdSharingSwiftDataCommittedImportFailure`.
///
/// The decorator also preserves the read/hydration capabilities consumed dynamically by normal
/// Core Data imports and public-ID repair convergence.
actor MutationPublishingHerdSharingImporter:
    HerdSharingImportApplying,
    CollaborationRevisionHydrating,
    HerdSharingExportSnapshotReading
{
    private let base: any HerdSharingImportApplying
        & CollaborationRevisionHydrating
        & HerdSharingExportSnapshotReading
    private let mutationCenter: ApplicationMutationCenter

    init(
        base: any HerdSharingImportApplying
            & CollaborationRevisionHydrating
            & HerdSharingExportSnapshotReading,
        mutationCenter: ApplicationMutationCenter
    ) {
        self.base = base
        self.mutationCenter = mutationCenter
    }

    func hydrateCollaborationRevisions(for herdPublicID: UUID) async throws {
        try await base.hydrateCollaborationRevisions(for: herdPublicID)
    }

    func makeExport(
        for herd: HerdSummary,
        storeDescription: String
    ) async throws -> HerdSharingSwiftDataExport {
        try await base.makeExport(
            for: herd,
            storeDescription: storeDescription
        )
    }

    func applyImport(
        _ snapshot: HerdSharingBridgeStoreSnapshot,
        pendingConflictReport: HerdSharingBridgeConflictReport?,
        failureInjector: HerdSharingBridgeFailureInjector
    ) async throws -> HerdSharingSwiftDataImportApplication {
        do {
            let application = try await base.applyImport(
                snapshot,
                pendingConflictReport: pendingConflictReport,
                failureInjector: failureInjector
            )
            await mutationCenter.recordSharedStoreImport()
            return application
        } catch let committedFailure as HerdSharingSwiftDataCommittedImportFailure {
            await mutationCenter.recordSharedStoreImport()
            throw committedFailure
        }
    }
}
