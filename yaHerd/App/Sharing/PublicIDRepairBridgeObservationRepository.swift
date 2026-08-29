import Foundation

/// Narrow, read-only adapter used by public-ID repair to observe the physical sharing bridge
/// without consulting local SwiftData ownership/creation guards. Duplicate local Herd rows are
/// one of the corruption states repair is expected to fix, so repair preparation must not require
/// those rows to be unique before it can identify the bridge that needs convergence.
@MainActor
protocol PublicIDRepairBridgeAccessReading: AnyObject {
    func fetchPublicIDRepairSharingAccess(for herd: HerdSummary) async throws -> HerdSharingAccess
}

extension HerdSharingCoreDataStore: PublicIDRepairBridgeAccessReading {
    func fetchPublicIDRepairSharingAccess(for herd: HerdSummary) async throws -> HerdSharingAccess {
        try await fetchSharingAccess(for: herd)
    }
}

/// Presents the physical bridge access reader through the existing coordinator dependency while
/// deliberately refusing every mutation. `DefaultPublicIDRepairBridgeCoordinator` uses only
/// `fetchSharingAccess`; bridge import/export remains owned by `PublicIDRepairBridgeExporting`.
@MainActor
final class PublicIDRepairBridgeObservationRepository: HerdSharingRepository {
    private let accessReader: any PublicIDRepairBridgeAccessReading

    init(accessReader: any PublicIDRepairBridgeAccessReading) {
        self.accessReader = accessReader
    }

    func fetchSharingReadiness(
        for herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) -> HerdSharingReadiness {
        guard herd != nil else { return .shareRootMissing }
        return storageMode == .iCloud ? .sharingAdapterAvailable : .iCloudSyncRequired
    }

    func fetchSharingAccess(
        for herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingAccess {
        guard storageMode == .iCloud else {
            throw HerdSharingActionError.iCloudSyncRequired
        }
        guard let herd else {
            throw HerdSharingActionError.shareRootMissing
        }
        let access = try await accessReader.fetchPublicIDRepairSharingAccess(for: herd)
        // Physical permission/location evidence is useful to repair, but this adapter must never
        // imply that the caller has authority to create a new share.
        return access.applyingCreationState(.unknown)
    }

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw HerdSharingActionError.sharingStateUnavailable
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw HerdSharingActionError.sharingStateUnavailable
    }

    func importSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw HerdSharingActionError.sharingStateUnavailable
    }

    func acceptPreventedSharedDeletes(
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw HerdSharingActionError.sharingStateUnavailable
    }

    func restoreLocalFields(
        _ selections: [HerdSharingLocalFieldRestoreSelection],
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw HerdSharingActionError.sharingStateUnavailable
    }

    func syncSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw HerdSharingActionError.sharingStateUnavailable
    }
}
