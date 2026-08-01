import Foundation
import SwiftData
import XCTest

@testable import yaHerd

extension SwiftDataHerdSharingActorTests {
  func testExportPreservesChildrenScopedThroughParentRelationships() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    let herd = Herd(
      name: "Relationship-scoped herd",
      createdAt: now,
      updatedAt: now
    )
    let pasture = Pasture(name: "Target pasture")
    pasture.herd = herd
    let animal = Animal(
      name: "",
      tagNumber: "101",
      birthDate: now,
      status: .active,
      pasture: pasture,
      sex: .female
    )
    animal.herd = herd
    let workingSession = WorkingSession(
      date: now,
      status: .finished,
      sourcePasture: pasture,
      protocolName: "Relationship scope",
      protocolItems: []
    )
    workingSession.herd = herd
    let fieldCheckSession = FieldCheckSession(
      startedAt: now,
      completedAt: now,
      pastureNameSnapshot: pasture.name,
      pastureID: pasture.publicID,
      pasture: pasture
    )

    context.insert(herd)
    context.insert(pasture)
    context.insert(animal)
    context.insert(workingSession)
    context.insert(fieldCheckSession)

    let tag = AnimalTag(
      number: animal.tagNumber,
      isPrimary: true,
      animal: animal
    )
    let movement = MovementRecord(
      date: now,
      fromPasture: nil,
      toPasture: pasture.name,
      animal: animal
    )
    let statusRecord = StatusRecord(
      date: now,
      oldStatus: .active,
      newStatus: .active,
      animal: animal
    )
    let healthRecord = HealthRecord(
      date: now,
      treatment: "Observation",
      animal: animal
    )
    let pregnancyCheck = PregnancyCheck(
      date: now,
      result: .open,
      animal: animal
    )
    let queueItem = WorkingQueueItem(
      queueOrder: 0,
      status: .done,
      collectedFromPasture: pasture,
      destinationPasture: pasture,
      animal: animal,
      session: workingSession
    )
    let treatmentRecord = WorkingTreatmentRecord(
      date: now,
      treatmentItemID: UUID(),
      itemName: "Observation",
      given: true,
      dose: WorkingTreatmentDose(amount: 1),
      animal: animal,
      session: workingSession
    )
    let animalCheck = FieldCheckAnimalCheck(
      animalIDSnapshot: animal.publicID,
      rosterTagNumber: animal.tagNumber,
      animalSex: .female,
      animal: animal,
      session: fieldCheckSession
    )
    let finding = FieldCheckFinding(
      recordedAt: now,
      type: .generalObservation,
      severity: .warning,
      status: .open,
      note: "Relationship-scoped finding",
      animalIDSnapshot: animal.publicID,
      pastureNameSnapshot: pasture.name,
      sessionIDSnapshot: fieldCheckSession.publicID,
      animal: animal,
      session: fieldCheckSession
    )

    context.insert(tag)
    context.insert(movement)
    context.insert(statusRecord)
    context.insert(healthRecord)
    context.insert(pregnancyCheck)
    context.insert(queueItem)
    context.insert(treatmentRecord)
    context.insert(animalCheck)
    context.insert(finding)
    try context.save()

    XCTAssertNil(fieldCheckSession.herd)
    XCTAssertNil(tag.herd)
    XCTAssertNil(movement.herd)
    XCTAssertNil(statusRecord.herd)
    XCTAssertNil(healthRecord.herd)
    XCTAssertNil(pregnancyCheck.herd)
    XCTAssertNil(queueItem.herd)
    XCTAssertNil(treatmentRecord.herd)
    XCTAssertNil(animalCheck.herd)
    XCTAssertNil(finding.herd)

    let actor = SwiftDataHerdSharingActor(modelContainer: container)
    let export = try await actor.makeExport(
      for: herd.toSummary(),
      storeDescription: "relationship-scope test"
    )

    func exportedIDs(_ step: HerdSharingBridgeStep) -> Set<UUID> {
      Set(export.snapshot.records(for: step).compactMap(\.parsedPublicID))
    }

    XCTAssertEqual(exportedIDs(.animalTags), [tag.publicID])
    XCTAssertEqual(exportedIDs(.movements), [movement.publicID])
    XCTAssertEqual(exportedIDs(.statusRecords), [statusRecord.publicID])
    XCTAssertEqual(exportedIDs(.healthRecords), [healthRecord.publicID])
    XCTAssertEqual(exportedIDs(.pregnancyChecks), [pregnancyCheck.publicID])
    XCTAssertEqual(exportedIDs(.workingQueueItems), [queueItem.publicID])
    XCTAssertEqual(exportedIDs(.workingTreatmentRecords), [treatmentRecord.publicID])
    XCTAssertEqual(exportedIDs(.fieldCheckSessions), [fieldCheckSession.publicID])
    XCTAssertEqual(exportedIDs(.fieldCheckAnimalChecks), [animalCheck.publicID])
    XCTAssertEqual(exportedIDs(.fieldCheckFindings), [finding.publicID])
  }
}
