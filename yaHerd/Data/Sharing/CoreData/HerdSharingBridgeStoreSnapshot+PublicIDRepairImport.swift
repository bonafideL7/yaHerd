import Foundation

struct PublicIDRepairBridgeResolutionRequired: LocalizedError, Equatable, Sendable {
    let issues: [PublicIDRepairUnresolvedReference]

    var errorDescription: String? {
        let details = issues.map { $0.reason }.joined(separator: " ")
        return "Shared-data convergence needs \(issues.count.formatted()) deliberate repair choice(s). \(details) Open Sync Diagnostics, select the intended repaired records, and finish convergence again."
    }
}

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

private struct PublicIDRepairReferenceCategoryKey: Hashable {
    let entityTypeRawValue: String
    let isEmbeddedTreatmentItem: Bool
}

private struct PublicIDRepairBridgeReferenceKey: Hashable {
    let entityName: String
    let recordPublicID: String
    let fieldName: String
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
        let resolutionPlan = try bridgeOnlyResolutionPlan(
            report: report,
            localRepairedSnapshot: localRepairedSnapshot,
            referenceGroups: referenceGroups,
            bridgeGroups: bridgeGroups
        )
        try rejectAmbiguousRepairTombstones(
            repairGroups: bridgeGroups,
            explicitlyResolvedTombstones: resolutionPlan.explicitlyResolvedTombstoneSourceURIs
        )

        var updatedRecords = recordsByStep
        for step in HerdSharingBridgeStep.entitySteps where step != .deletions {
            updatedRecords[step] = try translatedRepairImportRecords(
                for: step,
                localRepairedSnapshot: localRepairedSnapshot,
                bridgeGroups: bridgeGroups,
                referenceGroups: referenceGroups,
                selectedReferences: resolutionPlan.selectedReferences
            )
        }
        updatedRecords[.deletions] = records(for: .deletions).map { tombstone in
            guard let replacementID = resolutionPlan.selectedTombstonePublicIDs[tombstone.sourceObjectURI]
            else { return tombstone }
            return tombstone.replacingPublicID(replacementID)
        }

        return HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdPublicID,
            storeDescription: storeDescription,
            recordsByStep: updatedRecords
        )
    }

    private struct BridgeResolutionPlan {
        let selectedReferences: [PublicIDRepairBridgeReferenceKey: UUID]
        let selectedTombstonePublicIDs: [String: UUID]
        let explicitlyResolvedTombstoneSourceURIs: Set<String>
    }

    private func bridgeOnlyResolutionPlan(
        report: PublicIDRepairReport,
        localRepairedSnapshot: HerdSharingBridgeStoreSnapshot,
        referenceGroups: [PublicIDRepairReferenceGroup],
        bridgeGroups: [PublicIDRepairBridgeGroupKey: PublicIDRepairBridgeGroup]
    ) throws -> BridgeResolutionPlan {
        var issues: [PublicIDRepairUnresolvedReference] = []
        var selectedReferences: [PublicIDRepairBridgeReferenceKey: UUID] = [:]
        var selectedTombstones: [String: UUID] = [:]
        var resolvedTombstoneURIs = Set<String>()

        for step in HerdSharingBridgeStep.entitySteps where step != .deletions {
            let localByPublicID = Dictionary(grouping: localRepairedSnapshot.records(for: step)) {
                $0.publicID.lowercased()
            }
            let sourceEntityType = step.publicIDRepairEntityType

            for record in records(for: step) {
                if localByPublicID[record.publicID.lowercased()]?.count == 1 {
                    continue
                }

                for (fieldName, value) in record.attributes where fieldName != "publicID" {
                    guard case .string(let rawID) = value,
                          let referencedID = UUID(uuidString: rawID),
                          let target = publicIDRepairReferenceTarget(
                              entityName: record.entityName,
                              attributeName: fieldName
                          ),
                          let group = referenceGroups.first(where: {
                              $0.matches(target: target)
                                  && $0.key.retainedPublicID == referencedID
                                  && $0.resultingPublicIDs.count > 1
                          }) else {
                        continue
                    }

                    let candidates = publicIDRepairResolutionCandidates(
                        for: target,
                        group: group,
                        localRepairedSnapshot: localRepairedSnapshot,
                        report: report
                    )
                    let issue = PublicIDRepairUnresolvedReference(
                        entityType: sourceEntityType,
                        recordDescription: record.publicIDRepairDiagnosticDescription(
                            fallback: sourceEntityType.displayName
                        ),
                        stableRecordIdentifier: "bridge|\(record.entityName)|\(record.publicID.lowercased())",
                        fieldName: fieldName,
                        referencedPublicID: referencedID,
                        reason: "This shared record exists only in the bridge and still references repaired duplicate public ID \(referencedID.uuidString) through \(fieldName). Choose which repaired record this shared reference belongs to.",
                        candidates: candidates
                    )
                    if let selected = report.publicIDRepairSelectedBridgeCandidate(
                        for: issue,
                        candidates: candidates
                    ) {
                        selectedReferences[
                            PublicIDRepairBridgeReferenceKey(
                                entityName: record.entityName,
                                recordPublicID: record.publicID.lowercased(),
                                fieldName: fieldName
                            )
                        ] = selected.resultingPublicID
                    } else {
                        issues.append(issue)
                    }
                }
            }
        }

        for tombstone in records(for: .deletions) {
            guard case .string(let sourceEntityName) = tombstone.attributes["sourceEntityName"],
                  let tombstoneID = tombstone.parsedPublicID,
                  let group = bridgeGroups.values.first(where: {
                      $0.key.entityName == sourceEntityName
                          && $0.key.retainedPublicID == tombstoneID
                  }),
                  let entityType = PublicIDRepairEntityType.publicIDRepairType(
                      forBridgeEntityName: sourceEntityName
                  ) else {
                continue
            }

            let candidates = publicIDRepairResolutionCandidates(
                for: .entity(entityType),
                group: PublicIDRepairReferenceGroup(
                    key: PublicIDRepairReferenceGroupKey(
                        entityTypeRawValue: entityType.rawValue,
                        retainedPublicID: group.key.retainedPublicID,
                        isEmbeddedTreatmentItem: false
                    ),
                    resultingPublicIDs: group.resultingPublicIDs
                ),
                localRepairedSnapshot: localRepairedSnapshot,
                report: report
            )
            let issue = PublicIDRepairUnresolvedReference(
                kind: .canonicalRecord,
                entityType: entityType,
                recordDescription: "Shared deletion for \(entityType.displayName.lowercased())",
                stableRecordIdentifier: "bridge-tombstone|\(sourceEntityName)|\(tombstoneID.uuidString.lowercased())",
                fieldName: "deletionTargetPublicID",
                referencedPublicID: tombstoneID,
                reason: "This deletion was created while multiple physical records still shared the old public ID. Choose which repaired record the deletion was intended to remove.",
                candidates: candidates
            )
            if let selected = report.publicIDRepairSelectedBridgeCandidate(
                for: issue,
                candidates: candidates
            ) {
                selectedTombstones[tombstone.sourceObjectURI] = selected.resultingPublicID
                resolvedTombstoneURIs.insert(tombstone.sourceObjectURI)
            } else {
                issues.append(issue)
            }
        }

        if !issues.isEmpty {
            throw PublicIDRepairBridgeResolutionRequired(
                issues: issues.sorted { $0.id < $1.id }
            )
        }

        return BridgeResolutionPlan(
            selectedReferences: selectedReferences,
            selectedTombstonePublicIDs: selectedTombstones,
            explicitlyResolvedTombstoneSourceURIs: resolvedTombstoneURIs
        )
    }

    private func publicIDRepairResolutionCandidates(
        for target: PublicIDRepairReferenceTarget,
        group: PublicIDRepairReferenceGroup,
        localRepairedSnapshot: HerdSharingBridgeStoreSnapshot,
        report: PublicIDRepairReport
    ) -> [PublicIDRepairResolutionCandidate] {
        switch target {
        case .entity(let entityType):
            guard let step = entityType.publicIDRepairBridgeStep else { return [] }
            let records = localRepairedSnapshot.records(for: step).filter {
                guard let id = $0.parsedPublicID else { return false }
                return group.resultingPublicIDs.contains(id)
            }
            return records.compactMap { record in
                guard let id = record.parsedPublicID else { return nil }
                return PublicIDRepairResolutionCandidate(
                    stableRecordIdentifier: "bridge-candidate|\(entityType.rawValue)|\(id.uuidString.lowercased())",
                    recordDescription: record.publicIDRepairDiagnosticDescription(
                        fallback: entityType.displayName
                    ),
                    detail: record.publicIDRepairDiagnosticDetail,
                    resultingPublicID: id
                )
            }.sorted { lhs, rhs in
                if lhs.recordDescription != rhs.recordDescription {
                    return lhs.recordDescription < rhs.recordDescription
                }
                return lhs.resultingPublicID.uuidString < rhs.resultingPublicID.uuidString
            }

        case .embeddedTreatmentItem:
            return group.resultingPublicIDs.map { id in
                let matchingReplacement = report.replacements.first {
                    $0.replacementPublicID == id
                        && $0.stableRecordIdentifier.contains("|item-")
                }
                return PublicIDRepairResolutionCandidate(
                    stableRecordIdentifier: "bridge-treatment-candidate|\(id.uuidString.lowercased())",
                    recordDescription: matchingReplacement?.recordDescription ?? "Retained treatment item",
                    detail: matchingReplacement.map {
                        "Repaired treatment item from \($0.entityType.displayName.lowercased())"
                    } ?? "The treatment item that retained the original public ID",
                    resultingPublicID: id
                )
            }.sorted { $0.resultingPublicID.uuidString < $1.resultingPublicID.uuidString }
        }
    }

    private func translatedRepairImportRecords(
        for step: HerdSharingBridgeStep,
        localRepairedSnapshot: HerdSharingBridgeStoreSnapshot,
        bridgeGroups: [PublicIDRepairBridgeGroupKey: PublicIDRepairBridgeGroup],
        referenceGroups: [PublicIDRepairReferenceGroup],
        selectedReferences: [PublicIDRepairBridgeReferenceKey: UUID]
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
        for repairGroup in groupsForEntity.sorted(by: {
            $0.key.retainedPublicID.uuidString < $1.key.retainedPublicID.uuidString
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
                record.publicIDRepairPortableMatchFingerprint(referenceGroups: referenceGroups)
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

        let localByPublicID = Dictionary(grouping: localRecords) { $0.publicID.lowercased() }
        return try bridgeRecords.map { record in
            if let translated = translatedBySourceURI[record.sourceObjectURI] {
                return translated
            }
            guard let matches = localByPublicID[record.publicID.lowercased()],
                  matches.count == 1,
                  let localMatch = matches.first,
                  let publicID = record.parsedPublicID else {
                return record.applyingBridgeRepairSelections(selectedReferences)
            }
            return try record.translatingForPublicIDRepairImport(
                resultingPublicID: publicID,
                localMatch: localMatch,
                referenceGroups: referenceGroups
            )
        }
    }

    private func rejectAmbiguousRepairTombstones(
        repairGroups: [PublicIDRepairBridgeGroupKey: PublicIDRepairBridgeGroup],
        explicitlyResolvedTombstones: Set<String>
    ) throws {
        guard !repairGroups.isEmpty else { return }

        for tombstone in records(for: .deletions) {
            guard !explicitlyResolvedTombstones.contains(tombstone.sourceObjectURI),
                  case .string(let sourceEntityName) = tombstone.attributes["sourceEntityName"],
                  let tombstonePublicID = tombstone.parsedPublicID else {
                continue
            }

            if repairGroups.values.contains(where: { group in
                group.key.entityName == sourceEntityName
                    && group.key.retainedPublicID == tombstonePublicID
            }) {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "A shared deletion tombstone targets \(sourceEntityName) public ID \(tombstonePublicID.uuidString), which was shared by multiple physical records before repair. Public-ID repair stopped until Sync Diagnostics records which repaired record the deletion intended to remove."
                )
            }

            guard repairGroups.values.contains(where: { group in
                group.key.entityName == sourceEntityName
                    && group.resultingPublicIDs.contains(tombstonePublicID)
            }) else {
                continue
            }

            if let step = HerdSharingBridgeStep.publicIDRepairStep(forEntityName: sourceEntityName),
               records(for: step).contains(where: { $0.parsedPublicID == tombstonePublicID }) {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "The shared bridge contains both a live \(sourceEntityName) record and a deletion tombstone for repaired replacement public ID \(tombstonePublicID.uuidString). Public-ID repair stopped because the bridge state is contradictory."
                )
            }
        }
    }
}

private extension HerdSharingBridgeRecordSnapshot {
    func applyingBridgeRepairSelections(
        _ selectedReferences: [PublicIDRepairBridgeReferenceKey: UUID]
    ) -> HerdSharingBridgeRecordSnapshot {
        var updatedAttributes = attributes
        var changed = false
        for fieldName in attributes.keys where fieldName != "publicID" {
            let key = PublicIDRepairBridgeReferenceKey(
                entityName: entityName,
                recordPublicID: publicID.lowercased(),
                fieldName: fieldName
            )
            guard let selectedID = selectedReferences[key] else { continue }
            updatedAttributes[fieldName] = .string(selectedID.uuidString)
            changed = true
        }
        guard changed else { return self }
        return HerdSharingBridgeRecordSnapshot(
            entityName: entityName,
            publicID: publicID,
            sourceObjectURI: sourceObjectURI,
            attributes: updatedAttributes
        )
    }

    func replacingPublicID(_ publicID: UUID) -> HerdSharingBridgeRecordSnapshot {
        var updatedAttributes = attributes
        updatedAttributes["publicID"] = .string(publicID.uuidString)
        return HerdSharingBridgeRecordSnapshot(
            entityName: entityName,
            publicID: publicID.uuidString,
            sourceObjectURI: sourceObjectURI,
            attributes: updatedAttributes
        )
    }

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
            ) else { continue }
            let groups = referenceGroups.filter { $0.matches(target: target) }
            guard !groups.isEmpty, let localValue = localMatch.attributes[name] else { continue }

            switch (bridgeValue, localValue) {
            case (.string(let bridgeString), .string(let localString)):
                guard let bridgePublicID = UUID(uuidString: bridgeString),
                      let localPublicID = UUID(uuidString: localString),
                      bridgePublicID != localPublicID,
                      groups.contains(where: { group in
                          group.resultingPublicIDs.contains(bridgePublicID)
                              && group.resultingPublicIDs.contains(localPublicID)
                      }) else { continue }
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
            "publicID", "herdPublicID", "lastMirroredAt", "modifiedAt", "revision",
            "modifiedByParticipantID", "modifiedByDeviceID", "baseRevision",
            "baseFieldValuesJSON", "currentFieldValuesJSON",
        ]

        var components = ["entity|\(entityName)"]
        for key in attributes.keys.sorted() where !excludedAttributes.contains(key) {
            guard let value = attributes[key] else { continue }
            let target = publicIDRepairReferenceTarget(entityName: entityName, attributeName: key)
            let groups = target.map { target in
                referenceGroups.filter { $0.matches(target: target) }
            } ?? []
            components.append(
                "attribute|\(key)|\(value.publicIDRepairPortableMatchValue(referenceGroups: groups, target: target))"
            )
        }
        return components.joined(separator: "\n")
    }

    func publicIDRepairDiagnosticDescription(fallback: String) -> String {
        for key in ["name", "number", "normalizedNumber", "title", "note", "notes"] {
            if case .string(let value) = attributes[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return "\(fallback) \(publicID)"
    }

    var publicIDRepairDiagnosticDetail: String {
        let excluded: Set<String> = [
            "publicID", "herdPublicID", "lastMirroredAt", "modifiedAt", "revision",
            "modifiedByParticipantID", "modifiedByDeviceID", "baseRevision",
            "baseFieldValuesJSON", "currentFieldValuesJSON",
        ]
        let details = attributes.keys.sorted().compactMap { key -> String? in
            guard !excluded.contains(key), let value = attributes[key] else { return nil }
            switch value {
            case .null: return nil
            case .string(let value):
                guard !value.isEmpty else { return nil }
                return "\(key): \(value)"
            case .date(let value): return "\(key): \(value.formatted())"
            case .integer(let value): return "\(key): \(value)"
            case .double(let value): return "\(key): \(value)"
            case .boolean(let value): return "\(key): \(value ? "Yes" : "No")"
            case .data: return nil
            }
        }
        return details.prefix(4).joined(separator: " • ")
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
               let normalized = publicID.publicIDRepairNormalizedID(referenceGroups: referenceGroups) {
                return "uuid|\(normalized.uuidString.lowercased())"
            }
            return "string|\(Data(value.utf8).base64EncodedString())"
        case .date(let value): return "date|\(value.timeIntervalSinceReferenceDate.bitPattern)"
        case .data(let value):
            if case .embeddedTreatmentItem = target,
               let normalized = normalizedTreatmentItemsData(value, referenceGroups: referenceGroups) {
                return "treatment-items|\(normalized.base64EncodedString())"
            }
            return "data|\(value.base64EncodedString())"
        case .integer(let value): return "integer|\(value)"
        case .double(let value): return "double|\(value.bitPattern)"
        case .boolean(let value): return value ? "boolean|1" : "boolean|0"
        }
    }
}

private extension PublicIDRepairReferenceGroup {
    func matches(target: PublicIDRepairReferenceTarget) -> Bool {
        switch target {
        case .entity(let entityType):
            return !key.isEmbeddedTreatmentItem && key.entityTypeRawValue == entityType.rawValue
        case .embeddedTreatmentItem:
            return key.isEmbeddedTreatmentItem
        }
    }
}

private extension UUID {
    func publicIDRepairNormalizedID(
        referenceGroups: [PublicIDRepairReferenceGroup]
    ) -> UUID? {
        let retainedIDs = Set(referenceGroups.compactMap { group in
            group.resultingPublicIDs.contains(self) ? group.key.retainedPublicID : nil
        })
        guard !retainedIDs.isEmpty else { return nil }
        return retainedIDs.min { $0.uuidString < $1.uuidString }
    }
}

private func publicIDRepairReferenceTarget(
    entityName: String,
    attributeName: String
) -> PublicIDRepairReferenceTarget? {
    switch (entityName, attributeName) {
    case (SharedAnimalRecord.entityName, "tagColorID"): return .entity(.tagColorDefinition)
    case (SharedAnimalRecord.entityName, "statusReferenceID"): return .entity(.animalStatusReference)
    case (SharedAnimalRecord.entityName, "pasturePublicID"): return .entity(.pasture)
    case (SharedAnimalRecord.entityName, "sireAnimalPublicID"),
         (SharedAnimalRecord.entityName, "damAnimalPublicID"): return .entity(.animal)
    case (SharedAnimalTagRecord.entityName, "animalPublicID"): return .entity(.animal)
    case (SharedAnimalTagRecord.entityName, "colorID"): return .entity(.tagColorDefinition)
    case (SharedPastureRecord.entityName, "groupPublicID"): return .entity(.pastureGroup)
    case (SharedMovementRecord.entityName, "animalPublicID"),
         (SharedStatusRecord.entityName, "animalPublicID"),
         (SharedHealthRecord.entityName, "animalPublicID"),
         (SharedPregnancyCheckRecord.entityName, "animalPublicID"): return .entity(.animal)
    case (SharedStatusRecord.entityName, "oldStatusReferenceID"),
         (SharedStatusRecord.entityName, "newStatusReferenceID"): return .entity(.animalStatusReference)
    case (SharedHealthRecord.entityName, "workingSessionPublicID"),
         (SharedPregnancyCheckRecord.entityName, "workingSessionPublicID"): return .entity(.workingSession)
    case (SharedPregnancyCheckRecord.entityName, "sireAnimalPublicID"): return .entity(.animal)
    case (SharedWorkingProtocolTemplateRecord.entityName, "itemsJSON"),
         (SharedWorkingSessionRecord.entityName, "protocolItemsJSON"),
         (SharedWorkingTreatmentRecord.entityName, "treatmentItemID"): return .embeddedTreatmentItem
    case (SharedWorkingSessionRecord.entityName, "sourcePasturePublicID"): return .entity(.pasture)
    case (SharedWorkingQueueItemRecord.entityName, "sessionPublicID"),
         (SharedWorkingTreatmentRecord.entityName, "sessionPublicID"): return .entity(.workingSession)
    case (SharedWorkingQueueItemRecord.entityName, "animalPublicID"),
         (SharedWorkingTreatmentRecord.entityName, "animalPublicID"): return .entity(.animal)
    case (SharedWorkingQueueItemRecord.entityName, "collectedFromPasturePublicID"),
         (SharedWorkingQueueItemRecord.entityName, "destinationPasturePublicID"): return .entity(.pasture)
    case (SharedFieldCheckSessionRecord.entityName, "pasturePublicID"): return .entity(.pasture)
    case (SharedFieldCheckAnimalCheckRecord.entityName, "sessionPublicID"),
         (SharedFieldCheckFindingRecord.entityName, "sessionPublicID"),
         (SharedFieldCheckFindingRecord.entityName, "sessionIDSnapshot"): return .entity(.fieldCheckSession)
    case (SharedFieldCheckAnimalCheckRecord.entityName, "animalPublicID"),
         (SharedFieldCheckAnimalCheckRecord.entityName, "animalIDSnapshot"),
         (SharedFieldCheckFindingRecord.entityName, "animalPublicID"),
         (SharedFieldCheckFindingRecord.entityName, "animalIDSnapshot"): return .entity(.animal)
    case (SharedFieldCheckAnimalCheckRecord.entityName, "rosterTagColorID"),
         (SharedFieldCheckAnimalCheckRecord.entityName, "damRosterTagColorID"),
         (SharedFieldCheckFindingRecord.entityName, "animalDisplayTagColorIDSnapshot"): return .entity(.tagColorDefinition)
    default: return nil
    }
}

private func normalizedTreatmentItemsData(
    _ data: Data,
    referenceGroups: [PublicIDRepairReferenceGroup]
) -> Data? {
    guard var items = try? JSONDecoder().decode([WorkingProtocolItem].self, from: data) else { return nil }
    for index in items.indices {
        if let retainedID = items[index].id.publicIDRepairNormalizedID(referenceGroups: referenceGroups) {
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
        let matchingGroups = referenceGroups.filter { $0.resultingPublicIDs.contains(bridgeItem.id) }
        guard !matchingGroups.isEmpty else { continue }
        let contentFingerprint = bridgeItem.publicIDRepairTreatmentItemContentFingerprint
        let candidates = localItems.filter { localItem in
            localItem.publicIDRepairTreatmentItemContentFingerprint == contentFingerprint
                && matchingGroups.contains(where: { $0.resultingPublicIDs.contains(localItem.id) })
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
    func publicIDRepairSelectedBridgeCandidate(
        for issue: PublicIDRepairUnresolvedReference,
        candidates: [PublicIDRepairResolutionCandidate]
    ) -> PublicIDRepairResolutionCandidate? {
        guard let update = referenceUpdates.first(where: {
            $0.stableRecordIdentifier == issue.stableRecordIdentifier
                && $0.fieldName == issue.fieldName
                && $0.previousPublicID == issue.referencedPublicID
        }) else { return nil }
        return candidates.first { $0.resultingPublicID == update.repairedPublicID }
    }

    var publicIDRepairBridgeGroups: [PublicIDRepairBridgeGroupKey: PublicIDRepairBridgeGroup] {
        var adjacencyByEntity: [String: [UUID: Set<UUID>]] = [:]
        var retainedIDsByEntity: [String: Set<UUID>] = [:]

        for replacement in replacements {
            guard !replacement.stableRecordIdentifier.contains("|item-"),
                  let entityName = replacement.entityType.publicIDRepairImportBridgeEntityName else { continue }
            var adjacency = adjacencyByEntity[entityName, default: [:]]
            adjacency[replacement.retainedPublicID, default: []].insert(replacement.replacementPublicID)
            adjacency[replacement.replacementPublicID, default: []].insert(replacement.retainedPublicID)
            adjacencyByEntity[entityName] = adjacency
            retainedIDsByEntity[entityName, default: []].insert(replacement.retainedPublicID)
        }

        var groups: [PublicIDRepairBridgeGroupKey: PublicIDRepairBridgeGroup] = [:]
        for (entityName, retainedIDs) in retainedIDsByEntity {
            let adjacency = adjacencyByEntity[entityName, default: [:]]
            for retainedID in retainedIDs {
                let key = PublicIDRepairBridgeGroupKey(
                    entityName: entityName,
                    retainedPublicID: retainedID
                )
                groups[key] = PublicIDRepairBridgeGroup(
                    key: key,
                    resultingPublicIDs: publicIDRepairConnectedIDs(
                        from: retainedID,
                        adjacency: adjacency
                    )
                )
            }
        }
        return groups
    }

    var publicIDRepairReferenceGroups: [PublicIDRepairReferenceGroup] {
        var adjacencyByCategory: [PublicIDRepairReferenceCategoryKey: [UUID: Set<UUID>]] = [:]
        var retainedIDsByCategory: [PublicIDRepairReferenceCategoryKey: Set<UUID>] = [:]

        for replacement in replacements {
            let category = PublicIDRepairReferenceCategoryKey(
                entityTypeRawValue: replacement.entityType.rawValue,
                isEmbeddedTreatmentItem: replacement.stableRecordIdentifier.contains("|item-")
            )
            var adjacency = adjacencyByCategory[category, default: [:]]
            adjacency[replacement.retainedPublicID, default: []].insert(replacement.replacementPublicID)
            adjacency[replacement.replacementPublicID, default: []].insert(replacement.retainedPublicID)
            adjacencyByCategory[category] = adjacency
            retainedIDsByCategory[category, default: []].insert(replacement.retainedPublicID)
        }

        var groups: [PublicIDRepairReferenceGroup] = []
        for (category, retainedIDs) in retainedIDsByCategory {
            let adjacency = adjacencyByCategory[category, default: [:]]
            for retainedID in retainedIDs {
                let key = PublicIDRepairReferenceGroupKey(
                    entityTypeRawValue: category.entityTypeRawValue,
                    retainedPublicID: retainedID,
                    isEmbeddedTreatmentItem: category.isEmbeddedTreatmentItem
                )
                groups.append(
                    PublicIDRepairReferenceGroup(
                        key: key,
                        resultingPublicIDs: publicIDRepairConnectedIDs(
                            from: retainedID,
                            adjacency: adjacency
                        )
                    )
                )
            }
        }
        return groups
    }
}

private extension PublicIDRepairEntityType {
    var publicIDRepairImportBridgeEntityName: String? {
        publicIDRepairBridgeStep?.coreDataEntityName
    }

    var publicIDRepairBridgeStep: HerdSharingBridgeStep? {
        switch self {
        case .herd: .herd
        case .tagColorDefinition: .tagColorDefinitions
        case .animalStatusReference: .statusReferences
        case .pastureGroup: .pastureGroups
        case .pasture: .pastures
        case .animal: .animals
        case .animalTag: .animalTags
        case .movement: .movements
        case .statusRecord: .statusRecords
        case .workingProtocolTemplate: .workingProtocolTemplates
        case .workingSession: .workingSessions
        case .workingQueueItem: .workingQueueItems
        case .workingTreatmentRecord: .workingTreatmentRecords
        case .healthRecord: .healthRecords
        case .pregnancyCheck: .pregnancyChecks
        case .fieldCheckSession: .fieldCheckSessions
        case .fieldCheckAnimalCheck: .fieldCheckAnimalChecks
        case .fieldCheckFinding: .fieldCheckFindings
        }
    }

    static func publicIDRepairType(forBridgeEntityName entityName: String) -> PublicIDRepairEntityType? {
        allCases.first { $0.publicIDRepairImportBridgeEntityName == entityName }
    }
}

private extension HerdSharingBridgeStep {
    var publicIDRepairEntityType: PublicIDRepairEntityType {
        PublicIDRepairEntityType.publicIDRepairType(
            forBridgeEntityName: coreDataEntityName ?? ""
        ) ?? .herd
    }

    static func publicIDRepairStep(forEntityName entityName: String) -> HerdSharingBridgeStep? {
        entitySteps.first { $0 != .deletions && $0.coreDataEntityName == entityName }
    }
}

private func publicIDRepairConnectedIDs(
    from start: UUID,
    adjacency: [UUID: Set<UUID>]
) -> Set<UUID> {
    var visited: Set<UUID> = [start]
    var pending = [start]
    while let current = pending.popLast() {
        for neighbor in adjacency[current, default: []] where visited.insert(neighbor).inserted {
            pending.append(neighbor)
        }
    }
    return visited
}
