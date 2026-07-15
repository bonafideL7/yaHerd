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
  private let shareAdapter: CloudKitShareAdapter
  private(set) var pendingInvitation: HerdShareInvitation?

  init(shareAdapter: CloudKitShareAdapter) {
    self.shareAdapter = shareAdapter
  }

  var pendingSummary: HerdShareInvitationSummary? {
    pendingInvitation?.summary
  }

  var hasPendingInvitation: Bool {
    pendingInvitation != nil
  }

  func recordAcceptedShare(metadata: CKShare.Metadata, receivedAt: Date = Date.now) {
    if let pendingInvitation {
      shareAdapter.discardInvitation(pendingInvitation)
    }
    pendingInvitation = shareAdapter.registerInvitation(
      metadata: metadata,
      receivedAt: receivedAt
    )
  }

  func clearPendingInvitation() {
    if let pendingInvitation {
      shareAdapter.discardInvitation(pendingInvitation)
    }
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
