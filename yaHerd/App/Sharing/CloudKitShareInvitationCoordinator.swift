//
//  CloudKitShareInvitationCoordinator.swift
//  yaHerd
//

import CloudKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class CloudKitShareInvitationCoordinator {
    private(set) var pendingInvitation: HerdShareInvitation?

    var pendingSummary: HerdShareInvitationSummary? {
        pendingInvitation?.summary
    }

    var hasPendingInvitation: Bool {
        pendingInvitation != nil
    }

    func recordAcceptedShare(metadata: CKShare.Metadata, receivedAt: Date = Date.now) {
        pendingInvitation = HerdShareInvitation(
            metadata: metadata,
            receivedAt: receivedAt
        )
    }

    func clearPendingInvitation() {
        pendingInvitation = nil
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
