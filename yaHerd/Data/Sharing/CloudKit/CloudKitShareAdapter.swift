//
//  CloudKitShareAdapter.swift
//  yaHerd
//

import CloudKit
import Foundation

@MainActor
final class CloudKitShareAdapter {
  private var invitationMetadataByToken: [HerdShareToken: CKShare.Metadata] = [:]
  private var systemSharesByToken: [HerdShareToken: CloudKitSystemShare] = [:]

  func registerInvitation(
    metadata: CKShare.Metadata,
    receivedAt: Date = Date.now
  ) -> HerdShareInvitation {
    let token = HerdShareToken()
    invitationMetadataByToken[token] = metadata

    return HerdShareInvitation(
      token: token,
      receivedAt: receivedAt,
      containerIdentifier: metadata.containerIdentifier,
      shareIdentifier: metadata.share.recordID.recordName,
      rootIdentifier: metadata.hierarchicalRootRecordID?.recordName,
      ownerIdentifier: metadata.ownerIdentity.userRecordID?.recordName,
      ownerDisplayName: metadata.ownerIdentity.nameComponents?.formatted(),
      participantRole: participantRole(from: metadata.participantRole),
      permission: participantPermission(from: metadata.participantPermission),
      status: invitationStatus(from: metadata.participantStatus),
      shareURL: metadata.share.url
    )
  }

  func metadata(for invitation: HerdShareInvitation) throws -> CKShare.Metadata {
    guard let metadata = invitationMetadataByToken[invitation.token] else {
      throw HerdSharingActionError.shareInvitationMissing
    }
    return metadata
  }

  func discardInvitation(_ invitation: HerdShareInvitation) {
    invitationMetadataByToken.removeValue(forKey: invitation.token)
  }

  func registerSystemShare(_ systemShare: CloudKitSystemShare) -> HerdSharePresentationRequest {
    let token = HerdShareToken()
    systemSharesByToken[token] = systemShare

    return HerdSharePresentationRequest(
      token: token,
      title: systemShare.title,
      shareIdentifier: systemShare.share.recordID.recordName,
      shareURL: systemShare.share.url
    )
  }

  func systemShare(for request: HerdSharePresentationRequest) -> CloudKitSystemShare? {
    systemSharesByToken[request.token]
  }

  func discardSystemShare(for request: HerdSharePresentationRequest) {
    systemSharesByToken.removeValue(forKey: request.token)
  }

  private func participantRole(
    from role: CKShare.ParticipantRole
  ) -> HerdShareParticipantRole {
    switch role {
    case .owner:
      .owner
    case .administrator:
      .administrator
    case .privateUser:
      .privateUser
    case .publicUser:
      .publicUser
    case .unknown:
      .unknown
    @unknown default:
      .unknown
    }
  }

  private func participantPermission(
    from permission: CKShare.ParticipantPermission
  ) -> HerdShareParticipantPermission {
    switch permission {
    case .none:
      .none
    case .readOnly:
      .readOnly
    case .readWrite:
      .readWrite
    case .unknown:
      .unknown
    @unknown default:
      .unknown
    }
  }

  private func invitationStatus(
    from status: CKShare.ParticipantAcceptanceStatus
  ) -> HerdShareInvitationStatus {
    switch status {
    case .pending:
      .pending
    case .accepted:
      .accepted
    case .removed:
      .removed
    case .unknown:
      .unknown
    @unknown default:
      .unknown
    }
  }
}
