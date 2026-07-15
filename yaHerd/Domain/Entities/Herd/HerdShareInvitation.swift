//
//  HerdShareInvitation.swift
//  yaHerd
//

import Foundation

nonisolated enum HerdShareParticipantRole: String, Equatable, Sendable {
  case owner
  case administrator
  case privateUser
  case publicUser
  case unknown
}

nonisolated enum HerdShareParticipantPermission: String, Equatable, Sendable {
  case none
  case readOnly
  case readWrite
  case unknown
}

nonisolated enum HerdShareInvitationStatus: String, Equatable, Sendable {
  case pending
  case accepted
  case removed
  case unknown
}

nonisolated struct HerdShareInvitation: Equatable, Identifiable, Sendable {
  let id: UUID
  let token: HerdShareToken
  let receivedAt: Date
  let containerIdentifier: String?
  let shareIdentifier: String
  let rootIdentifier: String?
  let ownerIdentifier: String?
  let ownerDisplayName: String?
  let participantRole: HerdShareParticipantRole
  let permission: HerdShareParticipantPermission
  let status: HerdShareInvitationStatus
  let shareURL: URL?

  init(
    id: UUID = UUID(),
    token: HerdShareToken,
    receivedAt: Date = Date.now,
    containerIdentifier: String?,
    shareIdentifier: String,
    rootIdentifier: String?,
    ownerIdentifier: String?,
    ownerDisplayName: String?,
    participantRole: HerdShareParticipantRole,
    permission: HerdShareParticipantPermission,
    status: HerdShareInvitationStatus,
    shareURL: URL?
  ) {
    self.id = id
    self.token = token
    self.receivedAt = receivedAt
    self.containerIdentifier = containerIdentifier
    self.shareIdentifier = shareIdentifier
    self.rootIdentifier = rootIdentifier
    self.ownerIdentifier = ownerIdentifier
    self.ownerDisplayName = ownerDisplayName
    self.participantRole = participantRole
    self.permission = permission
    self.status = status
    self.shareURL = shareURL
  }

  var summary: HerdShareInvitationSummary {
    HerdShareInvitationSummary(
      id: id,
      receivedAt: receivedAt,
      containerIdentifier: containerIdentifier,
      shareRecordName: shareIdentifier,
      rootRecordName: rootIdentifier,
      ownerDisplayName: ownerDisplayName
    )
  }
}
