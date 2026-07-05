//
//  CloudKitShareInvitationCoordinator.swift
//  yaHerd
//

import CloudKit
import Foundation
import Observation
import SwiftUI

@Observable
final class CloudKitShareInvitationCoordinator {
    private(set) var pendingInvitation: PendingCloudKitShareInvitation?

    var pendingSummary: HerdShareInvitationSummary? {
        pendingInvitation?.summary
    }

    var hasPendingInvitation: Bool {
        pendingInvitation != nil
    }

    func recordAcceptedShare(metadata: CKShare.Metadata, receivedAt: Date = Date.now) {
        pendingInvitation = PendingCloudKitShareInvitation(
            metadata: metadata,
            receivedAt: receivedAt
        )
    }

    func clearPendingInvitation() {
        pendingInvitation = nil
    }
}

struct PendingCloudKitShareInvitation: Identifiable {
    let id = UUID()
    let metadata: CKShare.Metadata
    let receivedAt: Date

    var summary: HerdShareInvitationSummary {
        HerdShareInvitationSummary(
            id: id,
            receivedAt: receivedAt,
            containerIdentifier: metadata.containerIdentifier,
            shareRecordName: metadata.share.recordID.recordName,
            rootRecordName: metadata.rootRecordID.recordName,
            ownerDisplayName: metadata.ownerIdentity.nameComponents?.formatted()
        )
    }
}

private struct CloudKitShareInvitationCoordinatorKey: EnvironmentKey {
    static let defaultValue: CloudKitShareInvitationCoordinator? = nil
}

extension EnvironmentValues {
    var cloudKitShareInvitationCoordinator: CloudKitShareInvitationCoordinator? {
        get { self[CloudKitShareInvitationCoordinatorKey.self] }
        set { self[CloudKitShareInvitationCoordinatorKey.self] = newValue }
    }
}
