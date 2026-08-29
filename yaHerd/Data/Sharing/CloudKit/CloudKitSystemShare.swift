//
//  CloudKitSystemShare.swift
//  yaHerd
//

import CloudKit
import Foundation

@MainActor
final class CloudKitSystemShare {
  enum StopEvent: Equatable, Sendable {
    case started
    case completed
  }

  typealias StopObserver = @MainActor (StopEvent) async throws -> Void
  typealias StopPreparationObserver = @MainActor () throws -> Void

  let title: String
  let share: CKShare
  private let containerProvider: @MainActor () -> CKContainer
  private let persistUpdatedShareHandler: @MainActor (CKShare) async -> Void
  private let stopSharingHandler: @MainActor (CKShare) async throws -> Void
  private var persistedShareObserver: (@MainActor (URL, String) -> Void)?
  private var stopPreparationObserver: StopPreparationObserver?
  private var stopSharingObserver: StopObserver?

  var container: CKContainer {
    containerProvider()
  }

  init(
    title: String,
    share: CKShare,
    container: CKContainer,
    persistUpdatedShareHandler: @escaping @MainActor (CKShare) async -> Void,
    stopSharingHandler: @escaping @MainActor (CKShare) async throws -> Void
  ) {
    self.title = title
    self.share = share
    containerProvider = { container }
    self.persistUpdatedShareHandler = persistUpdatedShareHandler
    self.stopSharingHandler = stopSharingHandler
  }

  init(
    title: String,
    share: CKShare,
    containerProvider: @escaping @MainActor () -> CKContainer,
    persistUpdatedShareHandler: @escaping @MainActor (CKShare) async -> Void,
    stopSharingHandler: @escaping @MainActor (CKShare) async throws -> Void
  ) {
    self.title = title
    self.share = share
    self.containerProvider = containerProvider
    self.persistUpdatedShareHandler = persistUpdatedShareHandler
    self.stopSharingHandler = stopSharingHandler
  }

  func observePersistedShare(
    _ observer: @escaping @MainActor (URL, String) -> Void
  ) {
    persistedShareObserver = observer
  }

  func observeStopSharing(_ observer: @escaping StopObserver) {
    stopSharingObserver = observer
  }

  func observeStopPreparation(_ observer: @escaping StopPreparationObserver) {
    stopPreparationObserver = observer
  }

  func prepareToStopSharing() throws {
    try stopPreparationObserver?()
  }

  func persistUpdatedShare() async {
    await persistUpdatedShareHandler(share)
    guard let shareURL = share.url else { return }
    persistedShareObserver?(shareURL, share.recordID.recordName)
  }

  func stopSharing() async throws {
    try prepareToStopSharing()
    try await stopSharingObserver?(.started)
    try await stopSharingHandler(share)
    try await stopSharingObserver?(.completed)
  }
}
