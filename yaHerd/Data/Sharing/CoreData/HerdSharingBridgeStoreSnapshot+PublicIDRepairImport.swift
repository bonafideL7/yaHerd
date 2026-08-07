import Foundation

private struct PublicIDRepairBridgeGroupKey: Hashable {
    let entityName: String
    let retainedPublicID: UUID
}

private struct PublicIDRepairBridgeGroup {
    let key: PublicIDRepairBridgeGroupKey
    let resultingPublicIDs: Set<UUID>
}

extension HerdSharingBridgeStoreSnapshot {
    func preparingForPublicIDRepairImport(
        report: PublicIDRepairReport,
        localRepairedSnapshot: HerdSharingBridgeStoreSnapshot
    ) throws -> HerdSharingBridgeStoreSnapshot {
        let repairGroups = report.publicIDRepairBridgeGroups
        try rejectAmbiguousRepairTombstones(repairGroups: repairGroups)

        var updatedRecords = recordsByStep
        for step in HerdSharingBridgeStep.entitySteps where step != .deletions {
            updatedRecords[step] = try translatedRepairImportRecords(
                for: step,
                localRepairedSnapshot: localRepairedSnapshot,
                repairGroups: repairGroups
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
        repairGroups: [PublicIDRepairBridgeGroupKey: PublicIDRepairBridgeGroup]
    ) throws -> [HerdSharingBridgeRecordSnapshot] {
        let bridgeRecords = records(for: step)
        guard !bridgeRecords.isEmpty else { return [] }

        let localRecords = localRepairedSnapshot.records(for: step)
        let entityName = step.coreDataEntityName
        let groupsForEntity = repairGroups.values.filter { group in
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
                record.publicIDRepairPortableMatchFingerprint(repairGroups: repairGroups)
            }
            var usedLocalPublicIDs = Set<UUID>()

            for bridgeRecord in sourceRecords.sorted(by: { $0.sourceObjectURI < $1.sourceObjectURI }) {
                let fingerprint = bridgeRecord.publicIDRepairPortableMatchFingerprint(
                    repairGroups: repairGroups
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

                translatedBySourceURI[bridgeRecord.sourceObjectURI] = bridgeRecord
                    .translatingForPublicIDRepairImport(
                        resultingPublicID: resultingPublicID,
                        localMatch: localMatch,
                        repairGroups: repairGroups
                    )
            }
        }

        let localByPublicID = Dictionary(grouping: localRecords) { record in
            record.publicID.lowercased()
        }
        return bridgeRecords.map { record in
            if let translated = translatedBySourceURI[record.sourceObjectURI] {
                return translated
            }
            guard let matches = localByPublicID[record.publicID.lowercased()],
                  matches.count == 1,
                  let localMatch = matches.first,
                  let publicID = record.parsedPublicID else {
                return record
            }
            return record.translatingForPublicIDRepairImport(
                resultingPublicID: publicID,
                localMatch: localMatch,
                repairGroups: repairGroups
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
        repairGroups: [PublicIDRepairBridgeGroupKey: PublicIDRepairBridgeGroup]
    ) -> HerdSharingBridgeRecordSnapshot {
        var updatedAttributes = attributes
        updatedAttributes["publicID"] = .string(resultingPublicID.uuidString)

        for (name, bridgeValue) in attributes {
            guard name != "publicID",
                  case .string(let bridgeString) = bridgeValue,
                  let bridgePublicID = UUID(uuidString: bridgeString),
                  case .string(let localString) = localMatch.attributes[name],
                  let localPublicID = UUID(uuidString: localString),
                  bridgePublicID != localPublicID else {
                continue
            }

            let identifiesSameRepairGroup = repairGroups.values.contains { group in
                group.resultingPublicIDs.contains(bridgePublicID)
                    && group.resultingPublicIDs.contains(localPublicID)
            }
            if identifiesSameRepairGroup {
                updatedAttributes[name] = .string(localString)
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
        repairGroups: [PublicIDRepairBridgeGroupKey: PublicIDRepairBridgeGroup]
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
            components.append(
                "attribute|\(key)|\(value.publicIDRepairPortableMatchValue(repairGroups: repairGroups))"
            )
        }
        return components.joined(separator: "\n")
    }
}

private extension HerdSharingBridgeAttributeValue {
    func publicIDRepairPortableMatchValue(
        repairGroups: [PublicIDRepairBridgeGroupKey: PublicIDRepairBridgeGroup]
    ) -> String {
        switch self {
        case .null:
            return "null"
        case .string(let value):
            if let publicID = UUID(uuidString: value),
               let normalized = publicID.publicIDRepairNormalizedID(repairGroups: repairGroups) {
                return "uuid|\(normalized.uuidString.lowercased())"
            }
            return "string|\(Data(value.utf8).base64EncodedString())"
        case .date(let value):
            return "date|\(value.timeIntervalSinceReferenceDate.bitPattern)"
        case .data(let value):
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

private extension UUID {
    func publicIDRepairNormalizedID(
        repairGroups: [PublicIDRepairBridgeGroupKey: PublicIDRepairBridgeGroup]
    ) -> UUID? {
        let retainedIDs = Set(
            repairGroups.values.compactMap { group in
                group.resultingPublicIDs.contains(self) ? group.key.retainedPublicID : nil
            }
        )
        guard retainedIDs.count == 1 else { return nil }
        return retainedIDs.first
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
