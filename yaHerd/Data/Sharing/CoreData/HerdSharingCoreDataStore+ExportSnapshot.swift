//
//  HerdSharingCoreDataStore+ExportSnapshot.swift
//  yaHerd
//

import Foundation

enum HerdSharingBridgeExportSnapshotBuilder {
  static func makeExportStoreSnapshot(
    herd: HerdSummary,
    tagColorDefinitions: [TagColorDefinition],
    statusReferences: [AnimalStatusReference],
    animalTags: [AnimalTag],
    pastureGroups: [PastureGroup],
    pastures: [Pasture],
    animals: [Animal],
    movements: [MovementRecord],
    statusRecords: [StatusRecord],
    healthRecords: [HealthRecord],
    pregnancyChecks: [PregnancyCheck],
    workingProtocolTemplates: [WorkingProtocolTemplate],
    workingSessions: [WorkingSession],
    workingQueueItems: [WorkingQueueItem],
    workingTreatmentRecords: [WorkingTreatmentRecord],
    fieldCheckSessions: [FieldCheckSession],
    fieldCheckAnimalChecks: [FieldCheckAnimalCheck],
    fieldCheckFindings: [FieldCheckFinding],
    storeDescription: String
  ) throws -> HerdSharingBridgeStoreSnapshot {
    let mirroredAt = Date.now
    let herdPublicID = herd.publicID.uuidString
    var recordsByStep: [HerdSharingBridgeStep: [HerdSharingBridgeRecordSnapshot]] = [:]

    recordsByStep[.herd] = [
      try makeSnapshot(
        step: .herd,
        publicID: herdPublicID,
        values: values(
          ("name", herd.name),
          ("createdAt", herd.createdAt),
          ("updatedAt", herd.updatedAt),
          ("schemaVersion", NSNumber(value: herd.schemaVersion)),
          ("lastMirroredAt", mirroredAt)
        )
      )
    ]
    recordsByStep[.tagColorDefinitions] = try tagColorDefinitions.map { definition in
      try makeSnapshot(
        step: .tagColorDefinitions,
        publicID: definition.id.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("name", definition.name),
          ("prefix", definition.prefix),
          ("red", NSNumber(value: definition.red)),
          ("green", NSNumber(value: definition.green)),
          ("blue", NSNumber(value: definition.blue)),
          ("alpha", NSNumber(value: definition.alpha)),
          ("sortOrder", NSNumber(value: definition.sortOrder)),
          ("isHidden", NSNumber(value: definition.isHidden)),
          ("isDefault", NSNumber(value: definition.isDefault)),
          ("createdAt", definition.createdAt),
          ("updatedAt", definition.updatedAt),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.statusReferences] = try statusReferences.map { reference in
      try makeSnapshot(
        step: .statusReferences,
        publicID: reference.id.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("name", reference.name),
          ("baseStatusRawValue", reference.baseStatus.rawValue),
          ("createdAt", reference.createdAt),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.pastureGroups] = try pastureGroups.map { group in
      try makeSnapshot(
        step: .pastureGroups,
        publicID: group.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("name", group.name),
          ("grazeDays", NSNumber(value: group.grazeDays)),
          ("restDays", NSNumber(value: group.restDays)),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.pastures] = try pastures.map { pasture in
      try makeSnapshot(
        step: .pastures,
        publicID: pasture.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("name", pasture.name),
          ("sortOrder", NSNumber(value: pasture.sortOrder)),
          ("acreage", pasture.acreage.map { NSNumber(value: $0) }),
          ("usableAcreage", pasture.usableAcreage.map { NSNumber(value: $0) }),
          ("targetAcresPerHead", pasture.targetAcresPerHead.map { NSNumber(value: $0) }),
          ("lastGrazedDate", pasture.lastGrazedDate),
          ("groupPublicID", pasture.group?.publicID.uuidString),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.animals] = try animals.map { animal in
      try makeSnapshot(
        step: .animals,
        publicID: animal.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("name", animal.name),
          ("tagNumber", animal.tagNumber),
          ("tagColorID", animal.tagColorID?.uuidString),
          ("sexRawValue", animal.sex?.rawValue),
          ("birthDate", animal.birthDate),
          ("statusRawValue", animal.status.rawValue),
          ("saleDate", animal.saleDate),
          ("salePrice", animal.salePrice.map { NSNumber(value: $0) }),
          ("reasonSold", animal.reasonSold),
          ("deathDate", animal.deathDate),
          ("causeOfDeath", animal.causeOfDeath),
          ("statusReferenceID", animal.statusReferenceID?.uuidString),
          ("isSoftDeleted", NSNumber(value: animal.isSoftDeleted)),
          ("softDeletedAt", animal.softDeletedAt),
          ("softDeleteReason", animal.softDeleteReason),
          ("locationRawValue", animal.location.rawValue),
          ("pasturePublicID", animal.pasture?.publicID.uuidString),
          ("sireAnimalPublicID", animal.sireAnimal?.publicID.uuidString),
          ("damAnimalPublicID", animal.damAnimal?.publicID.uuidString),
          (
            "distinguishingFeaturesJSON",
            encode(
              animal.distinguishingFeatures.normalizedDistinguishingFeatureOrder,
              operation: "HerdSharingBridgeExportSnapshotBuilder.distinguishingFeaturesJSON"
            )
          ),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.animalTags] = try animalTags.map { tag in
      try makeSnapshot(
        step: .animalTags,
        publicID: tag.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("animalPublicID", tag.animal?.publicID.uuidString),
          ("number", tag.number),
          ("colorID", tag.colorID?.uuidString),
          ("isPrimary", NSNumber(value: tag.isPrimary)),
          ("isActive", NSNumber(value: tag.isActive)),
          ("assignedAt", tag.assignedAt),
          ("removedAt", tag.removedAt),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.movements] = try movements.map { movement in
      try makeSnapshot(
        step: .movements,
        publicID: movement.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("animalPublicID", movement.animal?.publicID.uuidString),
          ("date", movement.date),
          ("fromPasture", movement.fromPasture),
          ("toPasture", movement.toPasture),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.statusRecords] = try statusRecords.map { statusRecord in
      try makeSnapshot(
        step: .statusRecords,
        publicID: statusRecord.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("animalPublicID", statusRecord.animal?.publicID.uuidString),
          ("date", statusRecord.date),
          ("oldStatusRawValue", statusRecord.oldStatus.rawValue),
          ("newStatusRawValue", statusRecord.newStatus.rawValue),
          ("oldStatusReferenceID", statusRecord.oldStatusReferenceID?.uuidString),
          ("newStatusReferenceID", statusRecord.newStatusReferenceID?.uuidString),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.workingProtocolTemplates] = try workingProtocolTemplates.map { template in
      try makeSnapshot(
        step: .workingProtocolTemplates,
        publicID: template.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("name", template.name),
          (
            "itemsJSON",
            encode(
              template.items,
              operation: "HerdSharingBridgeExportSnapshotBuilder.itemsJSON"
            )
          ),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.workingSessions] = try workingSessions.map { session in
      try makeSnapshot(
        step: .workingSessions,
        publicID: session.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("date", session.date),
          ("statusRawValue", session.status.rawValue),
          ("sourcePasturePublicID", session.sourcePasture?.publicID.uuidString),
          ("protocolName", session.protocolName),
          (
            "protocolItemsJSON",
            encode(
              session.protocolItems,
              operation: "HerdSharingBridgeExportSnapshotBuilder.protocolItemsJSON"
            )
          ),
          ("currentQueueIndex", nil),
          ("notes", session.notes),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.workingQueueItems] = try workingQueueItems.map { queueItem in
      try makeSnapshot(
        step: .workingQueueItems,
        publicID: queueItem.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("sessionPublicID", queueItem.session?.publicID.uuidString),
          ("animalPublicID", queueItem.animal?.publicID.uuidString),
          ("queueOrder", nil),
          ("statusRawValue", queueItem.status.rawValue),
          ("completedAt", queueItem.completedAt),
          ("collectedFromPasturePublicID", queueItem.collectedFromPasture?.publicID.uuidString),
          ("destinationPasturePublicID", queueItem.destinationPasture?.publicID.uuidString),
          ("workNotes", queueItem.workNotes),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.workingTreatmentRecords] = try workingTreatmentRecords.map { treatment in
      try makeSnapshot(
        step: .workingTreatmentRecords,
        publicID: treatment.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("sessionPublicID", treatment.session?.publicID.uuidString),
          ("animalPublicID", treatment.animal?.publicID.uuidString),
          ("date", treatment.date),
          ("treatmentItemID", treatment.treatmentItemID.uuidString),
          ("itemName", treatment.itemName),
          ("given", NSNumber(value: treatment.given)),
          ("doseAmount", treatment.doseAmount.map { NSNumber(value: $0) }),
          ("doseUnitRawValue", treatment.doseUnit?.rawValue),
          ("administrationRouteRawValue", treatment.administrationRoute?.rawValue),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.healthRecords] = try healthRecords.map { healthRecord in
      try makeSnapshot(
        step: .healthRecords,
        publicID: healthRecord.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("animalPublicID", healthRecord.animal?.publicID.uuidString),
          ("date", healthRecord.date),
          ("treatment", healthRecord.treatment),
          ("notes", healthRecord.notes),
          ("workingSessionPublicID", healthRecord.workingSession?.publicID.uuidString),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.pregnancyChecks] = try pregnancyChecks.map { pregnancyCheck in
      try makeSnapshot(
        step: .pregnancyChecks,
        publicID: pregnancyCheck.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("animalPublicID", pregnancyCheck.animal?.publicID.uuidString),
          ("date", pregnancyCheck.date),
          ("resultRawValue", pregnancyCheck.result.rawValue),
          ("technician", pregnancyCheck.technician),
          (
            "estimatedDaysPregnant",
            pregnancyCheck.estimatedDaysPregnant.map { NSNumber(value: $0) }
          ),
          ("dueDate", pregnancyCheck.dueDate),
          ("sireAnimalPublicID", pregnancyCheck.sireAnimal?.publicID.uuidString),
          ("workingSessionPublicID", pregnancyCheck.workingSession?.publicID.uuidString),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.fieldCheckSessions] = try fieldCheckSessions.map { session in
      try makeSnapshot(
        step: .fieldCheckSessions,
        publicID: session.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("startedAt", session.startedAt),
          ("completedAt", session.completedAt),
          ("notes", session.notes),
          ("expectedHeadCountSnapshot", NSNumber(value: session.expectedHeadCountSnapshot)),
          ("quickCowCount", NSNumber(value: session.quickCowCount)),
          ("quickHeiferCount", NSNumber(value: session.quickHeiferCount)),
          ("quickCalfCount", NSNumber(value: session.quickCalfCount)),
          ("quickBullCount", NSNumber(value: session.quickBullCount)),
          ("quickSteerCount", NSNumber(value: session.quickSteerCount)),
          ("pastureNameSnapshot", session.pastureNameSnapshot),
          ("pastureArchivedAt", session.pastureArchivedAt),
          ("pasturePublicID", session.pasture?.publicID.uuidString ?? session.pastureID?.uuidString),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.fieldCheckAnimalChecks] = try fieldCheckAnimalChecks.map { check in
      try makeSnapshot(
        step: .fieldCheckAnimalChecks,
        publicID: check.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("sessionPublicID", check.session?.publicID.uuidString),
          ("animalPublicID", check.animal?.publicID.uuidString),
          ("animalIDSnapshot", check.animalIDSnapshot?.uuidString),
          ("rosterTagNumber", check.rosterTagNumber),
          ("rosterTagColorID", check.rosterTagColorID?.uuidString),
          ("damRosterTagNumber", check.damRosterTagNumber),
          ("damRosterTagColorID", check.damRosterTagColorID?.uuidString),
          ("animalName", check.animalName),
          ("animalSexRawValue", check.animalSex.rawValue),
          ("animalTypeRawValue", check.animalTypeSnapshot.rawValue),
          ("wasExpectedAtStart", NSNumber(value: check.wasExpectedAtStart)),
          ("countedAt", check.countedAt),
          ("missingConfirmedAt", check.missingConfirmedAt),
          ("note", check.note),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.fieldCheckFindings] = try fieldCheckFindings.map { finding in
      try makeSnapshot(
        step: .fieldCheckFindings,
        publicID: finding.publicID.uuidString,
        values: values(
          ("herdPublicID", herdPublicID),
          ("sessionPublicID", finding.session?.publicID.uuidString),
          ("animalPublicID", finding.animal?.publicID.uuidString),
          ("recordedAt", finding.recordedAt),
          ("typeRawValue", finding.type.rawValue),
          ("severityRawValue", finding.severity.rawValue),
          ("statusRawValue", finding.status.rawValue),
          ("note", finding.note),
          ("animalIDSnapshot", finding.animalIDSnapshot?.uuidString),
          ("animalDisplayTagNumberSnapshot", finding.animalDisplayTagNumberSnapshot),
          ("animalDisplayTagColorIDSnapshot", finding.animalDisplayTagColorIDSnapshot?.uuidString),
          ("animalNameSnapshot", finding.animalNameSnapshot),
          ("pastureNameSnapshot", finding.pastureNameSnapshot),
          ("sessionIDSnapshot", finding.sessionIDSnapshot?.uuidString),
          ("lastMirroredAt", mirroredAt)
        )
      )
    }
    recordsByStep[.deletions] = []

    return HerdSharingBridgeStoreSnapshot(
      herdPublicID: herd.publicID,
      storeDescription: storeDescription,
      recordsByStep: recordsByStep
    )
  }

  private static func makeSnapshot(
    step: HerdSharingBridgeStep,
    publicID: String,
    values: [String: Any]
  ) throws -> HerdSharingBridgeRecordSnapshot {
    try HerdSharingBridgeRecordSnapshot(
      step: step,
      publicID: publicID,
      values: values
    )
  }

  private static func values(_ pairs: (String, Any?)...) -> [String: Any] {
    var result: [String: Any] = [:]
    result.reserveCapacity(pairs.count)
    for (name, value) in pairs {
      guard let value else { continue }
      result[name] = value
    }
    return result
  }

  private static func encode<Value: Encodable>(
    _ value: Value,
    operation: String
  ) -> Data? {
    do {
      return try JSONEncoder().encode(value)
    } catch {
      PersistenceLog.decodeFailure(operation, error: error)
      return nil
    }
  }
}

private extension HerdSharingBridgeRecordSnapshot {
  init(step: HerdSharingBridgeStep, publicID: String, values: [String: Any]) throws {
    guard let entityName = step.coreDataEntityName,
      let entity = HerdSharingCoreDataModelFactory.makeCurrentModel().entitiesByName[entityName]
    else {
      throw HerdSharingBridgeSnapshotError.missingEntityDescription(
        step.coreDataEntityName ?? step.rawValue
      )
    }
    guard !publicID.isEmpty else {
      throw HerdSharingBridgeSnapshotError.missingPublicID(entityName: entityName)
    }

    let unknownNames = Set(values.keys).subtracting(entity.attributesByName.keys)
    guard unknownNames.isEmpty else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The \(entityName) export snapshot contains unknown attributes: \(unknownNames.sorted().joined(separator: ", "))."
      )
    }

    var rawValues = values
    rawValues["publicID"] = publicID
    var attributes: [String: HerdSharingBridgeAttributeValue] = [:]
    attributes.reserveCapacity(entity.attributesByName.count)
    for (name, description) in entity.attributesByName {
      attributes[name] = try HerdSharingBridgeAttributeValue(
        value: rawValues[name],
        attributeType: description.attributeType
      )
    }

    self.entityName = entityName
    self.publicID = publicID
    self.sourceObjectURI = "yaherd-snapshot://\(entityName)/\(publicID)"
    self.attributes = attributes
  }
}
