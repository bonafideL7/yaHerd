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
  private let cloudKitContainerIdentifier: String
  private let acceptedShareRecordIDProvider: ((NSManagedObjectID) -> CKRecord.ID?)?
  lazy var cloudKitContainer = CKContainer(identifier: cloudKitContainerIdentifier)

  var privateStore: NSPersistentStore?
  var sharedStore: NSPersistentStore?
  var isLoaded = false
  var isDeferringBridgeContextSaves = false
  let operationCoordinator: HerdSharingBridgeOperationCoordinator
  let acceptedParticipantProvenanceRecorder: @MainActor (UUID) -> Void
  let acceptedParticipantReferenceStore: (any HerdSharingAcceptedParticipantReferenceRecording)?
  let acceptedShareImportScopeStore: HerdSharingAcceptedShareImportScopeStore
  let acceptedParticipantRemoteVerifier: any HerdSharingRemoteAcceptedParticipantVerifying
  let acceptedScopeRemoteAbsenceConfirmationInterval: TimeInterval
  let nowProvider: @MainActor () -> Date

  init(
    containerIdentifier: String = ModelContainerFactory.cloudKitContainerIdentifier,
    storeDirectoryURL: URL? = nil,
    journalFileURL: URL? = nil,
    journal: HerdSharingBridgeJournal? = nil,
    acceptedParticipantProvenanceRecorder: @escaping @MainActor (UUID) -> Void = { _ in },
    acceptedParticipantReferenceStore: (any HerdSharingAcceptedParticipantReferenceRecording)? = nil,
    acceptedShareImportScopeStore: HerdSharingAcceptedShareImportScopeStore? = nil,
    acceptedShareRecordIDProvider: ((NSManagedObjectID) -> CKRecord.ID?)? = nil,
    acceptedParticipantRemoteVerifier: (any HerdSharingRemoteAcceptedParticipantVerifying)? = nil,
    acceptedScopeRemoteAbsenceConfirmationInterval: TimeInterval = 30,
    nowProvider: (@MainActor () -> Date)? = nil,
    failureInjector: HerdSharingBridgeFailureInjector = .disabled
  ) {
    cloudKitContainerIdentifier = containerIdentifier
    self.acceptedParticipantProvenanceRecorder = acceptedParticipantProvenanceRecorder
    self.acceptedParticipantReferenceStore = acceptedParticipantReferenceStore
    self.acceptedShareImportScopeStore = acceptedShareImportScopeStore
      ?? HerdSharingAcceptedShareImportScopeStore(
        participantReferenceStore: acceptedParticipantReferenceStore
      )
    self.acceptedShareRecordIDProvider = acceptedShareRecordIDProvider
    self.acceptedParticipantRemoteVerifier = acceptedParticipantRemoteVerifier
      ?? CloudKitHerdSharingRemoteAcceptedParticipantVerifier(
        containerIdentifier: containerIdentifier
      )
    self.acceptedScopeRemoteAbsenceConfirmationInterval =
      acceptedScopeRemoteAbsenceConfirmationInterval
    self.nowProvider = nowProvider ?? { Date.now }
    let model = HerdSharingCoreDataModelFactory.makeCurrentModel()
    persistentContainer = NSPersistentCloudKitContainer(
      name: Self.containerName,
      managedObjectModel: model
    )

    let directoryURL = storeDirectoryURL ?? Self.defaultStoreDirectoryURL()
    let resolvedJournal = journal ?? HerdSharingBridgeJournal(
      fileURL: journalFileURL
        ?? directoryURL.appendingPathComponent("HerdSharingSyncJournal.json")
    )
    operationCoordinator = HerdSharingBridgeOperationCoordinator(
      journal: resolvedJournal,
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

  func hasPendingAcceptedShareImportScope() async throws -> Bool {
    if acceptedShareImportScopeStore.hasCorruptPersistedState
      || acceptedShareImportScopeStore.hasCorruptRecoveryPending
    {
      return true
    }
    let scopes = try await acceptedShareImportScopeStore.pendingScopesForCurrentAccount()
    return !scopes.isEmpty
  }

  func acceptedShareRecordID(for objectID: NSManagedObjectID) -> CKRecord.ID? {
    if let acceptedShareRecordIDProvider {
      return acceptedShareRecordIDProvider(objectID)
    }
    return persistentContainer.recordID(for: objectID)
  }
}
