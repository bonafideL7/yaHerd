import CoreData
import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingImportCommitBoundaryTests: XCTestCase {
  private enum InjectedFailure: Error, Equatable {
    case afterStep(HerdSharingBridgeStep)
  }

  func testPostCommitFailurePersistsConflictReportForRetry() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let herdID = UUID()
    let animalID = UUID()

    let herd = Herd(
      publicID: herdID,
      name: "Local herd",
      createdAt: now,
      updatedAt: now
    )
    let animal = Animal(
      publicID: animalID,
      name: "Local name",
      tagNumber: "101",
      birthDate: now,
      status: .active,
      sex: .female
    )
    animal.herd = herd
    context.insert(herd)
    context.insert(animal)
    try context.save()

    let bridgeContext = try makeBridgeContext()
    let sharedHerd = SharedHerdRecord(context: bridgeContext)
    sharedHerd.mirror(herd.toSummary(), mirroredAt: now.addingTimeInterval(10))
    let remoteAnimal = Animal(
      publicID: animalID,
      name: "Remote name",
      tagNumber: "101",
      birthDate: now,
      status: .active,
      sex: .female
    )
    let sharedAnimal = SharedAnimalRecord(context: bridgeContext)
    sharedAnimal.mirror(
      remoteAnimal,
      herdPublicID: herdID,
      mirroredAt: now.addingTimeInterval(10)
    )
    try bridgeContext.save()

    let snapshot = HerdSharingBridgeStoreSnapshot(
      herdPublicID: herdID,
      storeDescription: "commit-boundary test",
      recordsByStep: [
        .herd: [try HerdSharingBridgeRecordSnapshot(record: sharedHerd)],
        .animals: [try HerdSharingBridgeRecordSnapshot(record: sharedAnimal)],
      ]
    )
    let failureInjector = HerdSharingBridgeFailureInjector { step in
      step == .persistentStoreCommit ? InjectedFailure.afterStep(step) : nil
    }

    let committedFailure: HerdSharingSwiftDataCommittedImportFailure
    do {
      _ = try HerdSharingSwiftDataImportEngine.apply(
        snapshot,
        pendingConflictReport: nil,
        failureInjector: failureInjector,
        in: context
      )
      XCTFail("Expected a post-commit failure.")
      return
    } catch let failure as HerdSharingSwiftDataCommittedImportFailure {
      committedFailure = failure
    }

    XCTAssertEqual(
      committedFailure.underlyingError as? InjectedFailure,
      .afterStep(.persistentStoreCommit)
    )
    XCTAssertTrue(committedFailure.completedSteps.contains(.persistentStoreCommit))
    XCTAssertEqual(committedFailure.conflictReport.existingLocalRecordUpdateCount, 1)
    let conflict = try XCTUnwrap(
      committedFailure.conflictReport.updatedRecordConflicts.first {
        $0.sourceEntityName == SharedAnimalRecord.entityName && $0.publicID == animalID
      }
    )
    XCTAssertTrue(
      conflict.fieldChanges.contains {
        $0.fieldName == "name" && $0.localValue.encodedValue == "Local name"
          && $0.sharedValue.encodedValue == "Remote name"
      }
    )
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<Animal>()).first { $0.publicID == animalID }?.name,
      "Remote name"
    )

    let journalURL = temporaryJournalURL(testName: #function)
    defer { try? FileManager.default.removeItem(at: journalURL.deletingLastPathComponent()) }
    let journal = HerdSharingBridgeJournal(fileURL: journalURL)
    let coordinator = HerdSharingBridgeOperationCoordinator(journal: journal)
    let operation = try await coordinator.begin(
      herdPublicID: herdID,
      direction: .importFromBridge,
      bridgeLocation: snapshot.storeDescription
    )

    await coordinator.recordCommittedImportFailure(
      committedFailure,
      operationID: operation.id
    )

    let failedOperation = try XCTUnwrap(await journal.unfinishedOperations().first)
    XCTAssertEqual(failedOperation.state, .failed)
    XCTAssertEqual(failedOperation.pendingConflictReport, committedFailure.conflictReport)
    XCTAssertTrue(failedOperation.completedSteps.contains(.persistentStoreCommit))

    let retry = try await HerdSharingBridgeOperationCoordinator(
      journal: HerdSharingBridgeJournal(fileURL: journalURL)
    ).begin(
      herdPublicID: herdID,
      direction: .importFromBridge,
      bridgeLocation: snapshot.storeDescription
    )
    XCTAssertEqual(retry.pendingConflictReport, committedFailure.conflictReport)
  }

  func testDuplicateBridgeRecordsUseStableSourceURITieBreaker() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let herdID = UUID()
    let animalID = UUID()
    let bridgeContext = try makeBridgeContext()

    let herd = Herd(
      publicID: herdID,
      name: "Duplicate record herd",
      createdAt: now,
      updatedAt: now
    )
    let sharedHerd = SharedHerdRecord(context: bridgeContext)
    sharedHerd.mirror(herd.toSummary(), mirroredAt: now)

    let firstAnimal = Animal(
      publicID: animalID,
      name: "First URI animal",
      tagNumber: "101",
      birthDate: now,
      status: .active,
      sex: .female
    )
    let secondAnimal = Animal(
      publicID: animalID,
      name: "Second URI animal",
      tagNumber: "102",
      birthDate: now,
      status: .active,
      sex: .female
    )
    let firstRecord = SharedAnimalRecord(context: bridgeContext)
    firstRecord.mirror(firstAnimal, herdPublicID: herdID, mirroredAt: now)
    let secondRecord = SharedAnimalRecord(context: bridgeContext)
    secondRecord.mirror(secondAnimal, herdPublicID: herdID, mirroredAt: now)
    try bridgeContext.save()

    let herdSnapshot = try HerdSharingBridgeRecordSnapshot(record: sharedHerd)
    let firstSnapshot = try HerdSharingBridgeRecordSnapshot(record: firstRecord)
    let secondSnapshot = try HerdSharingBridgeRecordSnapshot(record: secondRecord)
    let expectedSnapshot = [firstSnapshot, secondSnapshot].min {
      $0.sourceObjectURI < $1.sourceObjectURI
    }
    guard case .string(let expectedName) = expectedSnapshot?.attributes["name"] else {
      XCTFail("Expected the selected snapshot to contain an animal name.")
      return
    }

    let forwardName = try importedAnimalName(
      herdID: herdID,
      animalID: animalID,
      herdSnapshot: herdSnapshot,
      animalSnapshots: [firstSnapshot, secondSnapshot]
    )
    let reversedName = try importedAnimalName(
      herdID: herdID,
      animalID: animalID,
      herdSnapshot: herdSnapshot,
      animalSnapshots: [secondSnapshot, firstSnapshot]
    )

    XCTAssertEqual(forwardName, expectedName)
    XCTAssertEqual(reversedName, expectedName)
  }

  private func importedAnimalName(
    herdID: UUID,
    animalID: UUID,
    herdSnapshot: HerdSharingBridgeRecordSnapshot,
    animalSnapshots: [HerdSharingBridgeRecordSnapshot]
  ) throws -> String? {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let snapshot = HerdSharingBridgeStoreSnapshot(
      herdPublicID: herdID,
      storeDescription: "duplicate tie-breaker test",
      recordsByStep: [
        .herd: [herdSnapshot],
        .animals: animalSnapshots,
      ]
    )

    _ = try HerdSharingSwiftDataImportEngine.apply(
      snapshot,
      pendingConflictReport: nil,
      failureInjector: .disabled,
      in: context
    )
    return try context.fetch(FetchDescriptor<Animal>())
      .first { $0.publicID == animalID }?.name
  }

  private func makeBridgeContext() throws -> NSManagedObjectContext {
    let coordinator = NSPersistentStoreCoordinator(
      managedObjectModel: HerdSharingCoreDataModelFactory.makeCurrentModel()
    )
    try coordinator.addPersistentStore(
      ofType: NSInMemoryStoreType,
      configurationName: nil,
      at: nil
    )
    let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
    return context
  }

  private func temporaryJournalURL(testName: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("yaHerd-\(testName)-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("journal.json")
  }
}
