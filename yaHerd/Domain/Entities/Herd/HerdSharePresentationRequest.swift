//
//  HerdSharePresentationRequest.swift
//  yaHerd
//

import Foundation

nonisolated struct HerdSharePresentationRequest: Equatable, Identifiable, Sendable {
  let id: UUID
  let token: HerdShareToken
  let title: String
  let shareIdentifier: String
  let shareURL: URL?
  let shareRecordZoneName: String?
  let shareRecordOwnerName: String?
  let shareOwnerAccountRecordName: String?

  init(
    id: UUID = UUID(),
    token: HerdShareToken,
    title: String,
    shareIdentifier: String,
    shareURL: URL?,
    shareRecordZoneName: String? = nil,
    shareRecordOwnerName: String? = nil,
    shareOwnerAccountRecordName: String? = nil
  ) {
    self.id = id
    self.token = token
    self.title = title
    self.shareIdentifier = shareIdentifier
    self.shareURL = shareURL
    self.shareRecordZoneName = shareRecordZoneName
    self.shareRecordOwnerName = shareRecordOwnerName
    self.shareOwnerAccountRecordName = shareOwnerAccountRecordName
  }
}
