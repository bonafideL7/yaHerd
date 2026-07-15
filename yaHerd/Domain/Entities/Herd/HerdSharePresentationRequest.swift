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

  init(
    id: UUID = UUID(),
    token: HerdShareToken,
    title: String,
    shareIdentifier: String,
    shareURL: URL?
  ) {
    self.id = id
    self.token = token
    self.title = title
    self.shareIdentifier = shareIdentifier
    self.shareURL = shareURL
  }
}
