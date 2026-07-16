//
//  HerdSharingCoreDataStore.swift
//  yaHerd
//

import CloudKit
import CoreData
import Foundation
import SwiftData

@MainActor
final class HerdSharingCoreDataStore {
  static let containerName = "yaHerdSharingBridge"
  static let storeDirectoryName = "HerdSharingBridge"
  static let privateStoreFileName = "HerdSharingPrivate.sqlite"
  static let sharedStoreFileName = "HerdSharingShared.sqlite"

  let persistentContainer: NSPersistentCloudKitContainer
  let cloudKitContainer: CKContainer

  var privateStore: NSPersistentStore?
  var sharedStore: NSPersistentStore?
  var isLoaded = false
  var isDeferringBridgeContextSaves = false
  let operationCoordinator: HerdSharingBridgeOperationCoordinator

  init(
    containerIdentifier: String = ModelContainerFactory.cloudKitContainerIdentifier,
    storeDirectoryURL: URL? = nil,
    journalFileURL: URL? = nil,
    failureInjector: HerdSharingBridgeFailureInjector = .disabled
  ) {
    let model = HerdSharingCoreDataModelFactory.makeModel()
    persistentContainer = NSPersistentCloudKitContainer(
      name: Self.containerName,
      managedObjectModel: model
    )
    cloudKitContainer = CKContainer(identifier: containerIdentifier)

    let directoryURL = storeDirectoryURL ?? Self.defaultStoreDirectoryURL()
    let journal = HerdSharingBridgeJournal(
      fileURL: journalFileURL
        ?? directoryURL.appendingPathComponent("HerdSharingSyncJournal.json")
    )
    operationCoordinator = HerdSharingBridgeOperationCoordinator(
      journal: journal,
      failureInjector: failureInjector
    )
    persistentContainer.persistentStoreDescriptions = [
      Self.makeStoreDescription(
        url: directoryURL.appendingPathComponent(Self.privateStoreFileName),
        containerIdentifier: containerIdentifier,
        databaseScope: .private
      ),
      Self.makeStoreDescription(
        url: directoryURL.appendingPathComponent(Self.sharedStoreFileName),
        containerIdentifier: containerIdentifier,
        databaseScope: .shared
      ),
    ]
    persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
    persistentContainer.viewContext.mergePolicy = NSMergePolicy(
      merge: .mergeByPropertyObjectTrumpMergePolicyType
    )
  }
}
