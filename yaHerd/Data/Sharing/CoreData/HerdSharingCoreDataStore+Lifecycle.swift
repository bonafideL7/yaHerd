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
      var firstError: Error?
      var completedStoreCount = 0

      container.loadPersistentStores { _, error in
        if let error, firstError == nil {
          firstError = error
        }

        completedStoreCount += 1
        guard completedStoreCount == expectedStoreCount else { return }

        if let firstError {
          continuation.resume(throwing: firstError)
        } else {
          continuation.resume()
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
