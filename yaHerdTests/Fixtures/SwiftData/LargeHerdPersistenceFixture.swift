import Foundation
import SwiftData
@testable import yaHerd

@MainActor
enum LargeHerdPersistenceFixture {
  struct ExpectedCounts: Equatable {
    let animals: Int
    let animalTags: Int
    let movements: Int
    let healthRecords: Int
    let pregnancyChecks: Int
    let workingSessions: Int
    let workingQueueItems: Int
    let workingTreatmentRecords: Int
  }

  struct Result {
    let herd: HerdSummary
    let excludedHerd: HerdSummary
    let firstExcludedAnimalPublicID: UUID
    let expectedCounts: ExpectedCounts
  }

  static func insert(
    into context: ModelContext,
    animalCount: Int = 2_500,
    excludedAnimalCount: Int = 50
  ) throws -> Result {
    precondition(animalCount >= 500)

    let herd = Herd(
      publicID: stableUUID(namespace: 1, index: 1),
      name: "Performance Herd",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
    let excludedHerd = Herd(
      publicID: stableUUID(namespace: 2, index: 1),
      name: "Excluded Herd",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
    context.insert(herd)
    context.insert(excludedHerd)

    let pastures = (0..<8).map { index in
      let pasture = Pasture(
        publicID: stableUUID(namespace: 10, index: index),
        name: "Pasture \(index)",
        acreage: 40,
        usableAcreage: 35,
        targetAcresPerHead: 1.5,
        sortOrder: index
      )
      pasture.herd = herd
      context.insert(pasture)
      return pasture
    }

    let excludedPasture = Pasture(
      publicID: stableUUID(namespace: 20, index: 0),
      name: "Excluded Pasture",
      sortOrder: 0
    )
    excludedPasture.herd = excludedHerd
    context.insert(excludedPasture)

    let treatmentItem = WorkingProtocolItem(
      id: stableUUID(namespace: 30, index: 1),
      name: "Fixture vaccine",
      defaultQuantity: 2
    )
    let workingSessions = (0..<5).map { index in
      let session = WorkingSession(
        publicID: stableUUID(namespace: 31, index: index),
        date: Date(timeIntervalSince1970: 1_700_100_000 + Double(index * 86_400)),
        status: .finished,
        sourcePasture: pastures[index],
        protocolName: "Fixture protocol",
        protocolItems: [treatmentItem],
        notes: "Large-herd fixture"
      )
      session.herd = herd
      context.insert(session)
      return session
    }

    var movementCount = 0
    var healthRecordCount = 0
    var pregnancyCheckCount = 0
    var queueItemCount = 0
    var treatmentRecordCount = 0

    for index in 0..<animalCount {
      let animal = Animal(
        publicID: stableUUID(namespace: 100, index: index),
        name: "",
        tagNumber: String(format: "%05d", index),
        birthDate: Date(timeIntervalSince1970: 1_500_000_000 + Double(index * 3_600)),
        status: .active,
        pasture: pastures[index % pastures.count],
        sex: index.isMultiple(of: 2) ? .female : .male
      )
      animal.herd = herd
      context.insert(animal)

      let tag = AnimalTag(
        publicID: stableUUID(namespace: 101, index: index),
        number: animal.tagNumber,
        isPrimary: true,
        animal: animal
      )
      tag.herd = herd
      context.insert(tag)

      if index.isMultiple(of: 10) {
        let movement = MovementRecord(
          publicID: stableUUID(namespace: 102, index: index),
          date: Date(timeIntervalSince1970: 1_700_200_000 + Double(index)),
          fromPasture: "Pasture \((index + 7) % 8)",
          toPasture: "Pasture \(index % 8)",
          animal: animal
        )
        movement.herd = herd
        context.insert(movement)
        movementCount += 1
      }

      if index.isMultiple(of: 20) {
        let healthRecord = HealthRecord(
          publicID: stableUUID(namespace: 103, index: index),
          date: Date(timeIntervalSince1970: 1_700_300_000 + Double(index)),
          treatment: "Routine treatment",
          notes: "Fixture record",
          animal: animal
        )
        healthRecord.herd = herd
        context.insert(healthRecord)
        healthRecordCount += 1
      }

      if index.isMultiple(of: 25) {
        let pregnancyCheck = PregnancyCheck(
          publicID: stableUUID(namespace: 104, index: index),
          date: Date(timeIntervalSince1970: 1_700_400_000 + Double(index)),
          result: index.isMultiple(of: 50) ? .pregnant : .open,
          technician: "Fixture technician",
          animal: animal
        )
        pregnancyCheck.herd = herd
        context.insert(pregnancyCheck)
        pregnancyCheckCount += 1

        let session = workingSessions[min(index / 500, workingSessions.count - 1)]
        let queueItem = WorkingQueueItem(
          publicID: stableUUID(namespace: 105, index: index),
          queueOrder: index,
          status: .done,
          collectedFromPasture: animal.pasture,
          destinationPasture: animal.pasture,
          workNotes: "Fixture queue item",
          animal: animal,
          session: session
        )
        queueItem.herd = herd
        queueItem.completedAt = session.date
        context.insert(queueItem)
        queueItemCount += 1

        let treatmentRecord = WorkingTreatmentRecord(
          publicID: stableUUID(namespace: 106, index: index),
          date: session.date,
          treatmentItemID: treatmentItem.id,
          itemName: treatmentItem.name,
          given: true,
          dose: WorkingTreatmentDose(amount: 2),
          animal: animal,
          session: session
        )
        treatmentRecord.herd = herd
        context.insert(treatmentRecord)
        treatmentRecordCount += 1
      }
    }

    let firstExcludedAnimalPublicID = stableUUID(namespace: 200, index: 0)
    for index in 0..<excludedAnimalCount {
      let animal = Animal(
        publicID: stableUUID(namespace: 200, index: index),
        name: "Excluded \(index)",
        tagNumber: "X\(index)",
        birthDate: Date(timeIntervalSince1970: 1_600_000_000),
        status: .active,
        pasture: excludedPasture,
        sex: .female
      )
      animal.herd = excludedHerd
      context.insert(animal)

      let tag = AnimalTag(
        publicID: stableUUID(namespace: 201, index: index),
        number: animal.tagNumber,
        isPrimary: true,
        animal: animal
      )
      tag.herd = excludedHerd
      context.insert(tag)
    }

    try context.save()

    return Result(
      herd: herd.toSummary(),
      excludedHerd: excludedHerd.toSummary(),
      firstExcludedAnimalPublicID: firstExcludedAnimalPublicID,
      expectedCounts: ExpectedCounts(
        animals: animalCount,
        animalTags: animalCount,
        movements: movementCount,
        healthRecords: healthRecordCount,
        pregnancyChecks: pregnancyCheckCount,
        workingSessions: workingSessions.count,
        workingQueueItems: queueItemCount,
        workingTreatmentRecords: treatmentRecordCount
      )
    )
  }

  private static func stableUUID(namespace: Int, index: Int) -> UUID {
    let value = String(
      format: "%08X-0000-4000-8000-%012llX",
      namespace,
      Int64(index)
    )
    return UUID(uuidString: value)!
  }
}
