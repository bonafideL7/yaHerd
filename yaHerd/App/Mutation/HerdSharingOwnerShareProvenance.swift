import CloudKit
import Foundation

nonisolated struct HerdSharingRemoteOwnerShareReference: Codable, Equatable, Sendable {
    let shareURL: URL?
    let shareIdentifier: String
    let shareRecordZoneName: String?
    let shareRecordOwnerName: String?
    let shareOwnerAccountRecordName: String?

    init(
        shareURL: URL?,
        shareIdentifier: String,
        shareRecordZoneName: String? = nil,
        shareRecordOwnerName: String? = nil,
        shareOwnerAccountRecordName: String? = nil
    ) {
        self.shareURL = shareURL
        self.shareIdentifier = shareIdentifier
        self.shareRecordZoneName = shareRecordZoneName
        self.shareRecordOwnerName = shareRecordOwnerName
        self.shareOwnerAccountRecordName = shareOwnerAccountRecordName
    }

    var hasVerifiableLocator: Bool {
        shareURL != nil
            || (shareRecordZoneName != nil
                && shareRecordOwnerName != nil
                && shareOwnerAccountRecordName != nil)
    }
}

nonisolated enum HerdSharingRemoteOwnerShareStatus: Equatable, Sendable {
    case present
    case absent
}

@MainActor
protocol HerdSharingRemoteOwnerShareVerifying: AnyObject {
    func status(
        for reference: HerdSharingRemoteOwnerShareReference
    ) async throws -> HerdSharingRemoteOwnerShareStatus

    func hasAnyOwnerShare(
        forAccountRecordName expectedAccountRecordName: String
    ) async throws -> Bool

    func hasAnyOwnerShareForCurrentAccount() async throws -> Bool
}

extension HerdSharingRemoteOwnerShareVerifying {
    func hasAnyOwnerShare(
        forAccountRecordName expectedAccountRecordName: String
    ) async throws -> Bool {
        throw HerdSharingActionError.ownerBridgeVerificationRequired
    }

    func hasAnyOwnerShareForCurrentAccount() async throws -> Bool {
        throw HerdSharingActionError.ownerBridgeVerificationRequired
    }
}

@MainActor
final class CloudKitHerdSharingRemoteOwnerShareVerifier: HerdSharingRemoteOwnerShareVerifying {
    private let currentAccountRecordNameProvider: @MainActor () async throws -> String
    private let shareMetadataProvider: @MainActor (URL) async throws -> CKShare.Metadata
    private let privateRecordProvider: @MainActor (CKRecord.ID) async throws -> CKRecord
    private let recordZonesProvider: @MainActor () async throws -> [CKRecordZone]

    init(
        containerIdentifier: String = ModelContainerFactory.cloudKitContainerIdentifier,
        currentAccountRecordNameProvider: (@MainActor () async throws -> String)? = nil,
        shareMetadataProvider: (@MainActor (URL) async throws -> CKShare.Metadata)? = nil,
        privateRecordProvider: (@MainActor (CKRecord.ID) async throws -> CKRecord)? = nil,
        recordZonesProvider: (@MainActor () async throws -> [CKRecordZone])? = nil
    ) {
        self.currentAccountRecordNameProvider = currentAccountRecordNameProvider ?? {
            try await CKContainer(identifier: containerIdentifier).userRecordID().recordName
        }
        self.shareMetadataProvider = shareMetadataProvider ?? { shareURL in
            try await CKContainer(identifier: containerIdentifier).shareMetadata(for: shareURL)
        }
        self.privateRecordProvider = privateRecordProvider ?? { recordID in
            try await CKContainer(identifier: containerIdentifier).privateCloudDatabase.record(
                for: recordID
            )
        }
        self.recordZonesProvider = recordZonesProvider ?? {
            try await CKContainer(identifier: containerIdentifier).privateCloudDatabase
                .allRecordZones()
        }
    }

    func status(
        for reference: HerdSharingRemoteOwnerShareReference
    ) async throws -> HerdSharingRemoteOwnerShareStatus {
        do {
            let accountBeforeLookup = try await currentAccountRecordNameProvider()

            if let expectedOwnerAccount = reference.shareOwnerAccountRecordName {
                try HerdSharingOwnerShareProvenance.validateAccountCompatibility(
                    expectedOwnerAccountRecordName: expectedOwnerAccount,
                    currentAccountRecordName: accountBeforeLookup
                )
            } else if reference.shareURL == nil {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "The stored provisional owner-share provenance has no originating iCloud account identity. No stale owner state was reset."
                )
            }

            if let shareURL = reference.shareURL {
                let metadata: CKShare.Metadata
                do {
                    metadata = try await shareMetadataProvider(shareURL)
                } catch let error as CKError
                    where error.code == .unknownItem || error.code == .zoneNotFound
                {
                    guard reference.shareOwnerAccountRecordName != nil else {
                        throw HerdSharingActionError.bridgeConsistencyFailed(
                            "The stored owner-share URL has no originating iCloud account identity. Account-relative CloudKit absence cannot safely reset owner state."
                        )
                    }
                    try await validateAccountUnchanged(since: accountBeforeLookup)
                    return .absent
                }
                try HerdSharingOwnerShareProvenance.validateParticipantRole(
                    metadata.participantRole
                )
                let recordID = metadata.share.recordID
                guard recordID.recordName == reference.shareIdentifier else {
                    throw HerdSharingActionError.bridgeConsistencyFailed(
                        "The stored owner-share URL resolved to a different CloudKit share. No stale owner state was reset."
                    )
                }
                if let zoneName = reference.shareRecordZoneName,
                   let zoneOwnerName = reference.shareRecordOwnerName
                {
                    guard recordID.zoneID.zoneName == zoneName,
                          recordID.zoneID.ownerName == zoneOwnerName
                    else {
                        throw HerdSharingActionError.bridgeConsistencyFailed(
                            "The stored owner-share URL resolved to a different CloudKit record zone. No stale owner state was reset."
                        )
                    }
                }
                try await validateAccountUnchanged(since: accountBeforeLookup)
                return .present
            }

            guard let zoneName = reference.shareRecordZoneName,
                  let zoneOwnerName = reference.shareRecordOwnerName,
                  reference.shareOwnerAccountRecordName != nil
            else {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "The stored owner-share provenance has neither a share URL nor a complete CloudKit account and record-zone identity. No stale owner state was reset."
                )
            }

            let recordID = CKRecord.ID(
                recordName: reference.shareIdentifier,
                zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName)
            )
            let record: CKRecord
            do {
                record = try await privateRecordProvider(recordID)
            } catch let error as CKError
                where error.code == .unknownItem || error.code == .zoneNotFound
            {
                try await validateAccountUnchanged(since: accountBeforeLookup)
                return .absent
            }
            guard record is CKShare else {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "The stored owner-share record identity resolved to a non-share CloudKit record. No stale owner state was reset."
                )
            }
            try await validateAccountUnchanged(since: accountBeforeLookup)
            return .present
        } catch let error as HerdSharingActionError {
            throw error
        } catch {
            throw HerdSharingActionError.cloudKitSharingFailed(
                "Could not verify whether the prior owner share still exists in CloudKit: \(error.localizedDescription)"
            )
        }
    }

    func hasAnyOwnerShare(
        forAccountRecordName expectedAccountRecordName: String
    ) async throws -> Bool {
        do {
            let accountBeforeLookup = try await currentAccountRecordNameProvider()
            try HerdSharingOwnerShareProvenance.validateAccountCompatibility(
                expectedOwnerAccountRecordName: expectedAccountRecordName,
                currentAccountRecordName: accountBeforeLookup
            )
            let zones = try await recordZonesProvider()
            try await validateAccountUnchanged(since: accountBeforeLookup)
            return zones.contains { $0.share != nil }
        } catch let error as HerdSharingActionError {
            throw error
        } catch {
            throw HerdSharingActionError.cloudKitSharingFailed(
                "Could not verify whether any prior owner share remains in CloudKit: \(error.localizedDescription)"
            )
        }
    }

    func hasAnyOwnerShareForCurrentAccount() async throws -> Bool {
        do {
            let accountBeforeLookup = try await currentAccountRecordNameProvider()
            let zones = try await recordZonesProvider()
            try await validateAccountUnchanged(since: accountBeforeLookup)
            return zones.contains { $0.share != nil }
        } catch let error as HerdSharingActionError {
            throw error
        } catch {
            throw HerdSharingActionError.cloudKitSharingFailed(
                "Could not verify whether the current iCloud account already owns a yaHerd share: \(error.localizedDescription)"
            )
        }
    }

    private func validateAccountUnchanged(since expectedAccountRecordName: String) async throws {
        let currentAccountRecordName = try await currentAccountRecordNameProvider()
        guard currentAccountRecordName == expectedAccountRecordName else {
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        }
    }
}

@MainActor
protocol HerdSharingOwnerShareReferenceRecording: AnyObject {
    func reference(for herdPublicID: UUID) -> HerdSharingRemoteOwnerShareReference?
    func recoverableReference(for herdPublicID: UUID) throws -> HerdSharingRemoteOwnerShareReference?
    func hasBackedUpUnusableReference(for herdPublicID: UUID) -> Bool
    func prepareReferenceForRetirement(for herdPublicID: UUID) throws
    func record(
        _ reference: HerdSharingRemoteOwnerShareReference,
        for herdPublicID: UUID
    )
    func recordRecoverably(
        _ reference: HerdSharingRemoteOwnerShareReference,
        for herdPublicID: UUID
    ) throws
    func clearReference(for herdPublicID: UUID)
}

extension HerdSharingOwnerShareReferenceRecording {
    func recoverableReference(for herdPublicID: UUID) throws -> HerdSharingRemoteOwnerShareReference? {
        reference(for: herdPublicID)
    }

    func hasBackedUpUnusableReference(for herdPublicID: UUID) -> Bool { false }

    func prepareReferenceForRetirement(for herdPublicID: UUID) throws {}

    func recordRecoverably(
        _ reference: HerdSharingRemoteOwnerShareReference,
        for herdPublicID: UUID
    ) throws {
        record(reference, for: herdPublicID)
        guard self.reference(for: herdPublicID) == reference else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Owner-share provenance could not be persisted durably. Owner-share authority was not committed."
            )
        }
    }
}

@MainActor
final class HerdSharingSavedOwnerShareReferenceRecorder {
    private let referenceStore: any HerdSharingOwnerShareReferenceRecording
    private let herdPublicID: UUID
    private let presentationShareIdentifier: String
    private let presentationShareRecordZoneName: String?
    private let presentationShareRecordOwnerName: String?
    private let presentationShareOwnerAccountRecordName: String?

    init(
        referenceStore: any HerdSharingOwnerShareReferenceRecording,
        herdPublicID: UUID,
        presentation: HerdSharePresentationRequest
    ) {
        self.referenceStore = referenceStore
        self.herdPublicID = herdPublicID
        presentationShareIdentifier = presentation.shareIdentifier
        presentationShareRecordZoneName = presentation.shareRecordZoneName
        presentationShareRecordOwnerName = presentation.shareRecordOwnerName
        presentationShareOwnerAccountRecordName = presentation.shareOwnerAccountRecordName
    }

    func record(shareURL: URL, shareIdentifier: String) {
        guard shareIdentifier == presentationShareIdentifier,
              presentationShareOwnerAccountRecordName != nil
        else {
            return
        }
        let reference = HerdSharingRemoteOwnerShareReference(
            shareURL: shareURL,
            shareIdentifier: presentationShareIdentifier,
            shareRecordZoneName: presentationShareRecordZoneName,
            shareRecordOwnerName: presentationShareRecordOwnerName,
            shareOwnerAccountRecordName: presentationShareOwnerAccountRecordName
        )
        guard reference.hasVerifiableLocator else { return }
        try? referenceStore.recordRecoverably(reference, for: herdPublicID)
    }
}

@MainActor
enum HerdSharingOwnerShareProvenance {
    static func verifyRecordedShareIsAbsent(
        for herdPublicID: UUID,
        referenceStore: any HerdSharingOwnerShareReferenceRecording,
        remoteVerifier: any HerdSharingRemoteOwnerShareVerifying,
        allowMissingReference: Bool = false
    ) async throws {
        let reference = try referenceStore.recoverableReference(for: herdPublicID)

        guard let reference else {
            guard allowMissingReference else {
                throw HerdSharingActionError.ownerBridgeVerificationRequired
            }
            return
        }

        guard reference.hasVerifiableLocator else {
            guard let ownerAccountRecordName = reference.shareOwnerAccountRecordName else {
                throw HerdSharingActionError.ownerBridgeVerificationRequired
            }
            try referenceStore.prepareReferenceForRetirement(for: herdPublicID)
            try await verifyNoOwnerShareRemains(
                referenceStore: referenceStore,
                herdPublicID: herdPublicID,
                ownerAccountRecordName: ownerAccountRecordName,
                remoteVerifier: remoteVerifier
            )
            return
        }

        guard reference.shareOwnerAccountRecordName != nil else {
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        }

        guard try await remoteVerifier.status(for: reference) == .absent else {
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        }
    }

    static func verifyCurrentAccountHasNoOwnerShare(
        remoteVerifier: any HerdSharingRemoteOwnerShareVerifying
    ) async throws {
        guard try await !remoteVerifier.hasAnyOwnerShareForCurrentAccount() else {
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        }
    }

    static func validateAccountCompatibility(
        expectedOwnerAccountRecordName: String,
        currentAccountRecordName: String
    ) throws {
        guard expectedOwnerAccountRecordName == currentAccountRecordName else {
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        }
    }

    static func validateParticipantRole(_ participantRole: CKShare.ParticipantRole) throws {
        guard participantRole == .owner else {
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        }
    }

    @discardableResult
    static func recordPresentationReferenceIfVerifiable(
        _ presentation: HerdSharePresentationRequest,
        herdPublicID: UUID,
        referenceStore: any HerdSharingOwnerShareReferenceRecording
    ) -> Bool {
        let reference = HerdSharingRemoteOwnerShareReference(
            shareURL: presentation.shareURL,
            shareIdentifier: presentation.shareIdentifier,
            shareRecordZoneName: presentation.shareRecordZoneName,
            shareRecordOwnerName: presentation.shareRecordOwnerName,
            shareOwnerAccountRecordName: presentation.shareOwnerAccountRecordName
        )
        guard reference.hasVerifiableLocator,
              reference.shareOwnerAccountRecordName != nil
        else {
            return false
        }
        do {
            try referenceStore.recordRecoverably(reference, for: herdPublicID)
            return true
        } catch {
            return false
        }
    }

    private static func verifyNoOwnerShareRemains(
        referenceStore: any HerdSharingOwnerShareReferenceRecording,
        herdPublicID: UUID,
        ownerAccountRecordName: String,
        remoteVerifier: any HerdSharingRemoteOwnerShareVerifying
    ) async throws {
        guard try await !remoteVerifier.hasAnyOwnerShare(
            forAccountRecordName: ownerAccountRecordName
        ) else {
            throw HerdSharingActionError.ownerBridgeVerificationRequired
        }
        referenceStore.clearReference(for: herdPublicID)
    }
}
