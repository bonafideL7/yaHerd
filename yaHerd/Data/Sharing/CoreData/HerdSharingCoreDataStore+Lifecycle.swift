//
//  HerdSharingCoreDataStore+Lifecycle.swift
//  yaHerd
//

import CloudKit
import CoreData
import Foundation

extension HerdSharingCoreDataStore {
  func loadIfNeeded() async throws {
    guard !isLoaded else { return }
    let profilingStartedAt = Date()
    ReliabilityLog.syncEvent("HerdSharingCoreDataStore.loadIfNeeded.started")
    defer {
      PerformanceLog.logDuration(
        "HerdSharingCoreDataStore.loadIfNeeded", startedAt: profilingStartedAt)
      ReliabilityLog.syncEvent("HerdSharingCoreDataStore.loadIfNeeded.finished")
    }

    let directoryURL = persistentContainer.persistentStoreDescriptions
      .compactMap(\.url)
      .first?
      .deletingLastPathComponent()
    if let directoryURL {
      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: nil
      )
    }

    let container = persistentContainer
    let expectedStoreCount = container.persistentStoreDescriptions.count

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      guard expectedStoreCount > 0 else {
        continuation.resume()
        return
      }

      let tracker = PersistentStoreLoadTracker(
        expectedStoreCount: expectedStoreCount,
        continuation: continuation
      )

      container.loadPersistentStores { _, error in
        let errorDescription = error.map { String(describing: $0) }
        Task { @MainActor in
          await tracker.recordStoreCompletion(errorDescription: errorDescription)
        }
      }
    }

    privateStore = store(named: Self.privateStoreFileName)
    sharedStore = store(named: Self.sharedStoreFileName)
    isLoaded = true
  }

  private func store(named fileName: String) -> NSPersistentStore? {
    persistentContainer.persistentStoreCoordinator.persistentStores.first { store in
      store.url?.lastPathComponent == fileName
    }
  }

  static func makeStoreDescription(
    url: URL,
    containerIdentifier: String,
    databaseScope: CKDatabase.Scope
  ) -> NSPersistentStoreDescription {
    let description = NSPersistentStoreDescription(url: url)
    let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
    options.databaseScope = databaseScope
    description.cloudKitContainerOptions = options
    description.shouldMigrateStoreAutomatically = true
    description.shouldInferMappingModelAutomatically = true
    description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
    description.setOption(
      true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    return description
  }

  static func defaultStoreDirectoryURL() -> URL {
    let applicationSupportURL = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    return applicationSupportURL.appendingPathComponent(storeDirectoryName, isDirectory: true)
  }
}

private actor PersistentStoreLoadTracker {
  private let expectedStoreCount: Int
  private let continuation: CheckedContinuation<Void, Error>
  private var completedStoreCount = 0
  private var firstErrorDescription: String?
  private var didResume = false

  init(
    expectedStoreCount: Int,
    continuation: CheckedContinuation<Void, Error>
  ) {
    self.expectedStoreCount = expectedStoreCount
    self.continuation = continuation
  }

  func recordStoreCompletion(errorDescription: String?) {
    guard !didResume else { return }

    if firstErrorDescription == nil {
      firstErrorDescription = errorDescription
    }
    completedStoreCount += 1

    guard completedStoreCount >= expectedStoreCount else { return }
    didResume = true

    if let firstErrorDescription {
      continuation.resume(
        throwing: NSError(
          domain: "HerdSharingCoreDataStore.PersistentStoreLoad",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: firstErrorDescription]
        )
      )
    } else {
      continuation.resume()
    }
  }
}
