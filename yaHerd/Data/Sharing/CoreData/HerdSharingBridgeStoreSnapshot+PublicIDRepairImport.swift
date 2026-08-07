import Foundation

private struct PublicIDRepairBridgeGroupKey: Hashable {
    let entityName: String
    let retainedPublicID: UUID
}

private struct PublicIDRepairBridgeGroup {
    let key: PublicIDRepairBridgeGroupKey
    let resultingPublicIDs: Set<UUID>
}

private struct PublicIDRepairReferenceGroupKey: Hashable {
    let entityTypeRawValue: String
    let retainedPublicID: UUID
    let isEmbeddedTreatmentItem: Bool
}

private struct PublicIDRepairReferenceGroup {
    let key: PublicIDRepairReferenceGroupKey
    let resultingPublicIDs: Set<UUID>
}

private enum PublicIDRepairReferenceTarget {
    case entity(PublicIDRepairEntityType)
    case embeddedTreatmentItem
}

extension HerdSharingBridgeStoreSnapshot {
    func preparingForPublicIDRepairImport(
        report: PublicIDRepairReport,
        localRepairedSnapshot: HerdSharingBridgeStoreSnapshot
    ) throws -> HerdSharingBridgeStoreSnapshot {
        let bridgeGroups = report.publicIDRepairBridgeGroups
        let referenceGroups = report.publicIDRepairReferenceGroups
        try rejectAmbiguousRepairTombstones(repairGroups: bridgeGroups)

        var updatedRecords = recordsByStep
        for step in HerdSharingBridgeStep.entitySteps where step != .deletions {
            updatedRecords[step] = try translatedRepairImportRecords(
                for: step,
                localRepairedSnapshot: localRepairedSnapshot,
                bridgeGroups: bridgeGroups,
                referenceGroups: referenceGroups
            )
        }

        return HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdPublicID,
            storeDescription: storeDescription,
            recordsByStep: updatedRecords
        )
    }

    private func translatedRepairImportRecords(
        for step: HerdSharingBridgeStep,
        localRepairedSnapshot: HerdSharingBridgeStoreSnapshot,
        bridgeGroups: [PublicIDRepairBridgeGroupKey: PublicIDRepairBridgeGroup],
        referenceGroups: [PublicIDRepairReferenceGroup]
    ) throws -> [HerdSharingBridgeRecordSnapshot] {
        let bridgeRecords = records(for: step)
        guard !bridgeRecords.isEmpty else { return [] }

        let localRecords = localRepairedSnapshot.records(for: step)
        let entityName = step.coreDataEntityName
        let groupsForEntity = bridgeGroups.values.filter { group in
            group.key.entityName == entityName
        }

        let physicalDuplicateGroups = Dictionary(grouping: bridgeRecords) { record in
            record.publicID.lowercased()
        }.filter { $0.value.count > 1 }
        for (_, duplicateRecords) in physicalDuplicateGroups {
            guard let first = duplicateRecords.first,
                  let duplicatePublicID = first.parsedPublicID else {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "The shared bridge contains a duplicate \(step.rawValue) record with an invalid public ID. Public-ID repair stopped before importing shared data."
                )
            }
            let belongsToRepairGroup = groupsForEntity.contains { group in
                group.key.retainedPublicID == duplicatePublicID
            }
            guard belongsToRepairGroup else {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "The shared bridge contains \(duplicateRecords.count) physical \(first.entityName) records with public ID \(duplicatePublicID.uuidString), but the durable repair plan has no matching duplicate group. Public-ID repair stopped rather than discard a bridge record."
                )
            }
        }

        var translatedBySourceURI: [String: HerdSharingBridgeRecordSnapshot] = [:]
        for repairGroup in groupsForEntity.sorted(by: { lhs, rhs in
            lhs.key.retainedPublicID.uuidString < rhs.key.retainedPublicID.uuidString
        }) {
            let sourceRecords = bridgeRecords.filter {
                $0.parsedPublicID == repairGroup.key.retainedPublicID
            }
            guard !sourceRecords.isEmpty else { continue }

            let localCandidates = localRecords.filter { record in
                guard let publicID = record.parsedPublicID else { return false }
                return repairGroup.resultingPublicIDs.contains(publicID)
            }
            guard localCandidates.count >= sourceRecords.count else {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "The shared bridge contains more \(repairGroup.key.entityName) records for duplicate public ID \(repairGroup.key.retainedPublicID.uuidString) than the repaired local graph can identify. Public-ID repair stopped rather than merge records together."
                )
            }

            let localByFingerprint = Dictionary(grouping: localCandidates) { record in
                record.publicIDRepairPortableMatchFingerprint(
                    referenceGroups: referenceGroups
                )
            }
            var usedLocalPublicIDs = Set<UUID>()

            for bridgeRecord in sourceRecords.sorted(by: { $0.sourceObjectURI < $1.sourceObjectURI }) {
                let fingerprint = bridgeRecord.publicIDRepairPortableMatchFingerprint(
                    referenceGroups: referenceGroups
                )
                guard let matches = localByFingerprint[fingerprint],
                      matches.count == 1,
                      let localMatch = matches.first,
                      let resultingPublicID = localMatch.parsedPublicID,
                      usedLocalPublicIDs.insert(resultingPublicID).inserted else {
                    throw HerdSharingActionError.bridgeConsistencyFailed(
                        "Shared \(repairGroup.key.entityName) data still uses duplicate public ID \(repairGroup.key.retainedPublicID.uuidString), but its portable fields do not identify one repaired local record. Public-ID repair stopped rather than guess which record keeps or receives an ID."
                    )
                }

                translatedBySourceURI[bridgeRecord.sourceObjectURI] = try bridgeRecord
                    .translatingForPublicIDRepairImport(
                        resultingPublicID: resultingPublicID,
                        localMatch: localMatch,
                        referenceGroups: referenceGroups
                    )
            }
        }

        let localByPublicID = Dictionary(grouping: localRecords) { record in
            record.publicID.lowercased()
        }
        return try bridgeRecords.map { record in
            if let translated = translatedBySourceURI[record.sourceObjectURI] {
                return translated
            }
            guard let matches = localByPublicID[record.publicID.lowercased()],
                  matches.count == 1,
                  let localMatch = matches.first,
                  let publicID = record.parsedPublicID else {
                return record
            }
            return try record.translatingForPublicIDRepairImport(
                resultingPublicID: publicID,
                localMatch: localMatch,
                referenceGroups: referenceGroups
            )
        }
    }

    private func rejectAmbiguousRepairTombstones(
        repairGroups: [PublicIDRepairBridgeGroupKey: PublicIDRepairBridgeGroup]
    ) throws {
        guard !repairGroups.isEmpty else { return }

        for tombstone in records(for: .deletions) {
            guard case .string(let sourceEntityName) = tombstone.attributes["sourceEntityName"],
                  let tombstonePublicID = tombstone.parsedPublicID else {
                continue
            }

            guard let matchingGroup = repairGroups.values.first(where: { group in
                group.key.entityName == sourceEntityName
                    && group.resultingPublicIDs.contains(tombstonePublicID)
            }) else {
                continue
            }

            throw HerdSharingActionError.bridgeConsistencyFailed(
                "A shared deletion tombstone targets \(sourceEntityName) public ID \(tombstonePublicID.uuidString), which belongs to the repaired duplicate group that originally used \(matchingGroup.key.retainedPublicID.uuidString). The tombstone cannot identify which former physical duplicate it meant to delete, so public-ID repair stopped without applying the deletion."
            )
        }
    }
}

private extension HerdSharingBridgeRecordSnapshot {
    func translatingForPublicIDRepairImport(
        resultingPublicID: UUID,
        localMatch: HerdSharingBridgeRecordSnapshot,
        referenceGroups: [PublicIDRepairReferenceGroup]
    ) throws -> HerdSharingBridgeRecordSnapshot {
        var updatedAttributes = attributes
        updatedAttributes["publicID"] = .string(resultingPublicID.uuidString)

        for (name, bridgeValue) in attributes where name != "publicID" {
            guard let target = publicIDRepairReferenceTarget(
                entityName: entityName,
                attributeName: name
            ) else {
                continue
            }
            let groups = referenceGroups.filter { $0.matches(target: target) }
            guard !groups.isEmpty, let localValue = localMatch.attributes[name] else {
                continue
            }

            switch (bridgeValue, localValue) {
            case (.string(let bridgeString), .string(let localString)):
                guard let bridgePublicID = UUID(uuidString: bridgeString),
                      let localPublicID = UUID(uuidString: localString),
                      bridgePublicID != localPublicID,
                      groups.contains(where: { group in
                          group.resultingPublicIDs.contains(bridgePublicID)
                              && group.resultingPublicIDs.contains(localPublicID)
                      }) else {
                    continue
                }
                updatedAttributes[name] = .string(localString)

            case (.data(let bridgeData), .data(let localData)):
                guard case .embeddedTreatmentItem = target else { continue }
                updatedAttributes[name] = .data(
                    try translatingTreatmentItemIDs(
                        bridgeData: bridgeData,
                        localData: localData,
                        referenceGroups: groups,
                        recordDescription: "\(entityName).\(name)"
                    )
                )

            default:
                continue
            }
        }

        return HerdSharingBridgeRecordSnapshot(
            entityName: entityName,
            publicID: resultingPublicID.uuidString,
            sourceObjectURI: sourceObjectURI,
            attributes: updatedAttributes
        )
    }

    func publicIDRepairPortableMatchFingerprint(
        referenceGroups: [PublicIDRepairReferenceGroup]
    ) -> String {
        let excludedAttributes: Set<String> = [
            "publicID",
            "herdPublicID",
            "lastMirroredAt",
            "modifiedAt",
            "revision",
            "modifiedByParticipantID",
            "modifiedByDeviceID",
            "baseRevision",
            "baseFieldValuesJSON",
            "currentFieldValuesJSON",
        ]

        var components = ["entity|\(entityName)"]
        for key in attributes.keys.sorted() where !excludedAttributes.contains(key) {
            guard let value = attributes[key] else { continue }
            let target = publicIDRepairReferenceTarget(
                entityName: entityName,
                attributeName: key
            )
            let groups = target.map { target in
                referenceGroups.filter { $0.matches(target: target) }
            } ?? []
            components.append(
                "attribute|\(key)|\(value.publicIDRepairPortableMatchValue(referenceGroups: groups, target: target))"
            )
        }
        return components.joined(separator: "\n")
    }
}

private extension HerdSharingBridgeAttributeValue {
    func publicIDRepairPortableMatchValue(
        referenceGroups: [PublicIDRepairReferenceGroup],
        target: PublicIDRepairReferenceTarget?
    ) -> String {
        switch self {
        case .null:
            return "null"
        case .string(let value):
            if target != nil,
               let publicID = UUID(uuidString: value),
               let normalized = publicID.publicIDRepairNormalizedID(
                   referenceGroups: referenceGroups
               ) {
                return "uuid|\(normalized.uuidString.lowercased())"
            }
            return "string|\(Data(value.utf8).base64EncodedString())"
        case .date(let value):
            return "date|\(value.timeIntervalSinceReferenceDate.bitPattern)"
        case .data(let value):
            if case .embeddedTreatmentItem = target,
               let normalized = normalizedTreatmentItemsData(
                   value,
                   referenceGroups: referenceGroups
               ) {
                return "treatment-items|\(normalized.base64EncodedString())"
            }
            return "data|\(value.base64EncodedString())"
        case .integer(let value):
            return "integer|\(value)"
        case .double(let value):
            return "double|\(value.bitPattern)"
        case .boolean(let value):
            return value ? "boolean|1" : "boolean|0"
        }
    }
}

private extension PublicIDRepairReferenceGroup {
    func matches(target: PublicIDRepairReferenceTarget) -> Bool {
        switch target {
        case .entity(let entityType):
            return !key.isEmbeddedTreatmentItem
                && key.entityTypeRawValue == entityType.rawValue
        case .embeddedTreatmentItem:
            return key.isEmbeddedTreatmentItem
        }
    }
}

private extension UUID {
    func publicIDRepairNormalizedID(
        referenceGroups: [PublicIDRepairReferenceGroup]
    ) -> UUID? {
        let retainedIDs = Set(
            referenceGroups.compactMap { group in
                group.resultingPublicIDs.contains(self) ? group.key.retainedPublicID : nil
            }
        )
        guard retainedIDs.count == 1 else { return nil }
        return retainedIDs.first
    }
}

private func publicIDRepairReferenceTarget(
    entityName: String,
    attributeName: String
) -> PublicIDRepairReferenceTarget? {
    switch (entityName, attributeName) {
    case (SharedAnimalRecord.entityName, "tagColorID"):
        return .entity(.tagColorDefinition)
    case (SharedAnimalRecord.entityName, "statusReferenceID"):
        return .entity(.animalStatusReference)
    case (SharedAnimalRecord.entityName, "pasturePublicID"):
        return .entity(.pasture)
    case (SharedAnimalRecord.entityName, "sireAnimalPublicID"),
         (SharedAnimalRecord.entityName, "damAnimalPublicID"):
        return .entity(.animal)
    case (SharedAnimalTagRecord.entityName, "animalPublicID"):
        return .entity(.animal)
    case (SharedAnimalTagRecord.entityName, "colorID"):
        return .entity(.tagColorDefinition)
    case (SharedPastureRecord.entityName, "groupPublicID"):
        return .entity(.pastureGroup)
    case (SharedMovementRecord.entityName, "animalPublicID"),
         (SharedStatusRecord.entityName, "animalPublicID"),
         (SharedHealthRecord.entityName, "animalPublicID"),
         (SharedPregnancyCheckRecord.entityName, "animalPublicID"):
        return .entity(.animal)
    case (SharedStatusRecord.entityName, "oldStatusReferenceID"),
         (SharedStatusRecord.entityName, "newStatusReferenceID"):
        return .entity(.animalStatusReference)
    case (SharedHealthRecord.entityName, "workingSessionPublicID"),
         (SharedPregnancyCheckRecord.entityName, "workingSessionPublicID"):
        return .entity(.workingSession)
    case (SharedPregnancyCheckRecord.entityName, "sireAnimalPublicID"):
        return .entity(.animal)
    case (SharedWorkingProtocolTemplateRecord.entityName, "itemsJSON"),
         (SharedWorkingSessionRecord.entityName, "protocolItemsJSON"),
         (SharedWorkingTreatmentRecord.entityName, "treatmentItemID"):
        return .embeddedTreatmentItem
    case (SharedWorkingSessionRecord.entityName, "sourcePasturePublicID"):
        return .entity(.pasture)
    case (SharedWorkingQueueItemRecord.entityName, "sessionPublicID"),
         (SharedWorkingTreatmentRecord.entityName, "sessionPublicID"):
        return .entity(.workingSession)
    case (SharedWorkingQueueItemRecord.entityName, "animalPublicID"),
         (SharedWorkingTreatmentRecord.entityName, "animalPublicID"):
        return .entity(.animal)
    case (SharedWorkingQueueItemRecord.entityName, "collectedFromPasturePublicID"),
         (SharedWorkingQueueItemRecord.entityName, "destinationPasturePublicID"):
        return .entity(.pasture)
    case (SharedFieldCheckSessionRecord.entityName, "pasturePublicID"):
        return .entity(.pasture)
    case (SharedFieldCheckAnimalCheckRecord.entityName, "sessionPublicID"),
         (SharedFieldCheckFindingRecord.entityName, "sessionPublicID"),
         (SharedFieldCheckFindingRecord.entityName, "sessionIDSnapshot"):
        return .entity(.fieldCheckSession)
    case (SharedFieldCheckAnimalCheckRecord.entityName, "animalPublicID"),
         (SharedFieldCheckAnimalCheckRecord.entityName, "animalIDSnapshot"),
         (SharedFieldCheckFindingRecord.entityName, "animalPublicID"),
         (SharedFieldCheckFindingRecord.entityName, "animalIDSnapshot"):
        return .entity(.animal)
    case (SharedFieldCheckAnimalCheckRecord.entityName, "rosterTagColorID"),
         (SharedFieldCheckAnimalCheckRecord.entityName, "damRosterTagColorID"),
         (SharedFieldCheckFindingRecord.entityName, "animalDisplayTagColorIDSnapshot"):
        return .entity(.tagColorDefinition)
    default:
        return nil
    }
}

private func normalizedTreatmentItemsData(
    _ data: Data,
    referenceGroups: [PublicIDRepairReferenceGroup]
) -> Data? {
    guard var items = try? JSONDecoder().decode([WorkingProtocolItem].self, from: data) else {
        return nil
    }
    for index in items.indices {
        if let retainedID = items[index].id.publicIDRepairNormalizedID(
            referenceGroups: referenceGroups
        ) {
            items[index].id = retainedID
        }
    }
    return try? publicIDRepairTreatmentItemsEncoder().encode(items)
}

private func translatingTreatmentItemIDs(
    bridgeData: Data,
    localData: Data,
    referenceGroups: [PublicIDRepairReferenceGroup],
    recordDescription: String
) throws -> Data {
    guard var bridgeItems = try? JSONDecoder().decode([WorkingProtocolItem].self, from: bridgeData),
          let localItems = try? JSONDecoder().decode([WorkingProtocolItem].self, from: localData) else {
        throw HerdSharingActionError.bridgeConsistencyFailed(
            "The shared bridge contains unreadable treatment-plan data in \(recordDescription). Public-ID repair stopped rather than replace embedded IDs blindly."
        )
    }

    for index in bridgeItems.indices {
        let bridgeItem = bridgeItems[index]
        let matchingGroups = referenceGroups.filter {
            $0.resultingPublicIDs.contains(bridgeItem.id)
        }
        guard !matchingGroups.isEmpty else { continue }

        let contentFingerprint = bridgeItem.publicIDRepairTreatmentItemContentFingerprint
        let candidates = localItems.filter { localItem in
            localItem.publicIDRepairTreatmentItemContentFingerprint == contentFingerprint
                && matchingGroups.contains(where: { group in
                    group.resultingPublicIDs.contains(localItem.id)
                })
        }
        guard candidates.count == 1, let localItem = candidates.first else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "The shared bridge contains a treatment-plan item with duplicate public ID \(bridgeItem.id.uuidString), but its portable fields do not identify one repaired local item in \(recordDescription). Public-ID repair stopped rather than guess which item receives an ID."
            )
        }
        bridgeItems[index].id = localItem.id
    }

    return try publicIDRepairTreatmentItemsEncoder().encode(bridgeItems)
}

private func publicIDRepairTreatmentItemsEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}

private extension WorkingProtocolItem {
    var publicIDRepairTreatmentItemContentFingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let doseData = (try? encoder.encode(suggestedDose)) ?? Data()
        return "name|\(Data(name.utf8).base64EncodedString())|dose|\(doseData.base64EncodedString())"
    }
}

private extension PublicIDRepairReport {
    var publicIDRepairBridgeGroups: [PublicIDRepairBridgeGroupKey: PublicIDRepairBridgeGroup] {
        var IDsByKey: [PublicIDRepairBridgeGroupKey: Set<UUID>] = [:]

        for replacement in replacements {
            guard !replacement.stableRecordIdentifier.contains("|item-"),
                  let entityName = replacement.entityType.publicIDRepairImportBridgeEntityName else {
                continue
            }
            let key = PublicIDRepairBridgeGroupKey(
                entityName: entityName,
                retainedPublicID: replacement.retainedPublicID
            )
            IDsByKey[key, default: [replacement.retainedPublicID]]
                .insert(replacement.replacementPublicID)
        }

        return Dictionary(
            uniqueKeysWithValues: IDsByKey.map { key, resultingPublicIDs in
                (
                    key,
                    PublicIDRepairBridgeGroup(
                        key: key,
                        resultingPublicIDs: resultingPublicIDs
                    )
                )
            }
        )
    }

    var publicIDRepairReferenceGroups: [PublicIDRepairReferenceGroup] {
        var IDsByKey: [PublicIDRepairReferenceGroupKey: Set<UUID>] = [:]
        for replacement in replacements {
            let key = PublicIDRepairReferenceGroupKey(
                entityTypeRawValue: replacement.entityType.rawValue,
                retainedPublicID: replacement.retainedPublicID,
                isEmbeddedTreatmentItem: replacement.stableRecordIdentifier.contains("|item-")
            )
            IDsByKey[key, default: [replacement.retainedPublicID]]
                .insert(replacement.replacementPublicID)
        }
        return IDsByKey.map { key, resultingPublicIDs in
            PublicIDRepairReferenceGroup(
                key: key,
                resultingPublicIDs: resultingPublicIDs
            )
        }
    }
}

private extension PublicIDRepairEntityType {
    var publicIDRepairImportBridgeEntityName: String? {
        let step: HerdSharingBridgeStep
        switch self {
        case .herd: step = .herd
        case .tagColorDefinition: step = .tagColorDefinitions
        case .animalStatusReference: step = .statusReferences
        case .pastureGroup: step = .pastureGroups
        case .pasture: step = .pastures
        case .animal: step = .animals
        case .animalTag: step = .animalTags
        case .movement: step = .movements
        case .statusRecord: step = .statusRecords
        case .workingProtocolTemplate: step = .workingProtocolTemplates
        case .workingSession: step = .workingSessions
        case .workingQueueItem: step = .workingQueueItems
        case .workingTreatmentRecord: step = .workingTreatmentRecords
        case .healthRecord: step = .healthRecords
        case .pregnancyCheck: step = .pregnancyChecks
        case .fieldCheckSession: step = .fieldCheckSessions
        case .fieldCheckAnimalCheck: step = .fieldCheckAnimalChecks
        case .fieldCheckFinding: step = .fieldCheckFindings
        }
        return step.coreDataEntityName
    }
}
