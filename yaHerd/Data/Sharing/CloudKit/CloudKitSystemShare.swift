//
//  CloudKitSystemShare.swift
//  yaHerd
//

import CloudKit
import Foundation

@MainActor
final class CloudKitSystemShare {
  let title: String
  let share: CKShare
  let container: CKContainer
  private let persistUpdatedShareHandler: @MainActor (CKShare) async -> Void
  private let stopSharingHandler: @MainActor (CKShare) async -> Void

  init(
    title: String,
    share: CKShare,
    container: CKContainer,
    persistUpdatedShareHandler: @escaping @MainActor (CKShare) async -> Void,
    stopSharingHandler: @escaping @MainActor (CKShare) async -> Void
  ) {
    self.title = title
    self.share = share
    self.container = container
    self.persistUpdatedShareHandler = persistUpdatedShareHandler
    self.stopSharingHandler = stopSharingHandler
  }

  func persistUpdatedShare() async {
    await persistUpdatedShareHandler(share)
  }

  func stopSharing() async {
    await stopSharingHandler(share)
  }
}
