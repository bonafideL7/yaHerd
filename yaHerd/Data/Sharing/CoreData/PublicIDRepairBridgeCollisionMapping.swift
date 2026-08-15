import Foundation

private struct PublicIDRepairManifestBridgeCollision {
    let entityType: PublicIDRepairEntityType
    let originalPublicID: UUID
    let retainedOwnerHerdPublicID: UUID
    let replacementByHerdPublicID: [UUID: UUID]

    var id: String {
        "\(entityType.rawValue)|\(originalPublicID.uuidString.lowercased())"
    }
}

private extension PublicIDRepairManifest {
    var bridgeCollisions: [PublicIDRepairManifestBridgeCollision] {
        let collisionMappings = recordMappings.filter { $0.origin == .bridgeCollision }
        let grouped = Dictionary(grouping: collisionMappings) {
            "\($0.entityType.rawValue)|\($0.originalPublicID.uuidString.lowercased())"
        }
        return grouped.compactMap { _, mappings in
            let retained = mappings.filter {
                $0.retainedOriginalID && $0.finalPublicID == $0.originalPublicID
            }
            guard retained.count == 1,
                  let retainedOwner = retained[0].owningHerdPublicID else {
                return nil
            }
            let replacements = mappings.filter { !$0.retainedOriginalID }.compactMap { mapping
                -> (UUID, UUID)? in
                guard let owner = mapping.owningHerdPublicID else { return nil }
                return (owner, mapping.finalPublicID)
            }
            return PublicIDRepairManifestBridgeCollision(
                entityType: retained[0].entityType,
                originalPublicID: retained[0].originalPublicID,
                retainedOwnerHerdPublicID: retainedOwner,
                replacementByHerdPublicID: Dictionary(uniqueKeysWithValues: replacements)
            )
        }.sorted { $0.id < $1.id }
    }
}

extension HerdSharingBridgeStoreSnapshot {
    /// Replays durable manifest mappings before the normal duplicate-ID translation runs. The
    /// bridge does not choose canonical records, ownership, or replacement IDs here.
    func applyingPublicIDRepairBridgeCollisionResolutions(
        report: PublicIDRepairReport
    ) throws -> HerdSharingBridgeStoreSnapshot {
        guard report.manifest.contradictions.isEmpty else {
            throw HerdSharingActionError.bridgeConsistencyFailed(
                "Public-ID repair contains contradictory durable identity mappings. Shared-data convergence remains blocked."
            )
        }

        let collisions = report.manifest.bridgeCollisions
        guard !collisions.isEmpty else { return self }

        var updatedRecords = recordsByStep
        for collision in collisions {
            guard herdPublicID != collision.retainedOwnerHerdPublicID,
                  let replacementID = collision.replacementByHerdPublicID[herdPublicID] else {
                continue
            }
            guard let repairedStep = publicIDRepairBridgeStep(for: collision.entityType),
                  repairedStep != .herd,
                  repairedStep != .deletions else {
                throw HerdSharingActionError.bridgeConsistencyFailed(
                    "Public-ID repair cannot replay a shared identity mapping for \(collision.entityType.displayName.lowercased())."
                )
            }

            // A transaction can prepare unrelated Herd roots because they may contain references.
            // Only a Herd proven to contain exactly one source entity or tombstone consumes its
            // Herd-specific identity mapping. Multiple physical records with the old ID must stay
            // untouched here so the portable fingerprint matcher can assign distinct manifest IDs
            // instead of flattening them onto one Herd-level replacement.
            guard ownsExactlyOnePublicIDRepairIdentity(
                step: repairedStep,
                retainedPublicID: collision.originalPublicID
            ) else {
                continue
            }

            for step in HerdSharingBridgeStep.entitySteps where step != .deletions {
                updatedRecords[step] = updatedRecords[step, default: []].map { record in
                    record.applyingPublicIDRepairCrossHerdResolution(
                        repairedStep: repairedStep,
                        entityType: collision.entityType,
                        retainedPublicID: collision.originalPublicID,
                        replacementPublicID: replacementID
                    )
                }
            }
            updatedRecords[.deletions] = updatedRecords[.deletions, default: []].map { tombstone in
                guard tombstone.parsedPublicID == collision.originalPublicID,
                      tombstone.deletedSourceEntityNameForPublicIDRepair
                        == repairedStep.coreDataEntityName else {
                    return tombstone
                }
                return tombstone.replacingPublicIDForRepair(replacementID)
            }
        }

        return HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdPublicID,
            storeDescription: storeDescription,
            recordsByStep: updatedRecords
        )
    }

    /// Entity/public-ID identities after any repair translation. Tombstones claim the identity of
    /// their source entity because the normal importer resolves deletions through that same key.
    var publicIDRepairRecordIdentities: Set<PublicIDRepairBridgeRecordIdentity> {
        let identitySteps = HerdSharingBridgeStep.entitySteps.filter {
            $0 != .herd && $0 != .deletions
        }
        var identities = Set(identitySteps.flatMap { step in
            records(for: step).compactMap { record in
                record.parsedPublicID.map {
                    PublicIDRepairBridgeRecordIdentity(step: step, publicID: $0)
                }
            }
        })

        for tombstone in records(for: .deletions) {
            guard let publicID = tombstone.parsedPublicID,
                  let sourceEntityName = tombstone.deletedSourceEntityNameForPublicIDRepair,
                  let sourceStep = identitySteps.first(where: {
                      $0.coreDataEntityName == sourceEntityName
                  }) else {
                continue
            }
            identities.insert(
                PublicIDRepairBridgeRecordIdentity(
                    step: sourceStep,
                    publicID: publicID
                )
            )
        }
        return identities
    }

    private func ownsExactlyOnePublicIDRepairIdentity(
        step: HerdSharingBridgeStep,
        retainedPublicID: UUID
    ) -> Bool {
        let liveMatches = records(for: step).filter {
            $0.parsedPublicID == retainedPublicID
        }
        if liveMatches.count == 1 {
            return true
        }
        if liveMatches.count > 1 {
            return false
        }

        let tombstoneMatches = records(for: .deletions).filter { tombstone in
            tombstone.parsedPublicID == retainedPublicID
                && tombstone.deletedSourceEntityNameForPublicIDRepair == step.coreDataEntityName
        }
        return tombstoneMatches.count == 1
    }
}

extension HerdSharingBridgeRecordSnapshot {
    var deletedSourceEntityNameForPublicIDRepair: String? {
        guard entityName == SharedDeletedRecord.entityName,
              case .string(let sourceEntityName) = attributes["sourceEntityName"] else {
            return nil
        }
        return sourceEntityName
    }

    func publicIDRepairSemanticDescription(fallback: String) -> String {
        for key in ["name", "number", "normalizedNumber", "tagNumber", "title", "note", "notes"] {
            if case .string(let value) = attributes[key],
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return fallback
    }

    var publicIDRepairSemanticDetail: String {
        let excluded: Set<String> = [
            "publicID", "herdPublicID", "lastMirroredAt", "modifiedAt", "revision",
            "modifiedByParticipantID", "modifiedByDeviceID", "baseRevision",
            "baseFieldValuesJSON", "currentFieldValuesJSON",
        ]
        let details = attributes.keys.sorted().compactMap { key -> String? in
            guard !excluded.contains(key), let value = attributes[key] else { return nil }
            switch value {
            case .null:
                return nil
            case .string(let value):
                guard !value.isEmpty else { return nil }
                return "\(key): \(value)"
            case .date(let value):
                return "\(key): \(value.formatted())"
            case .integer(let value):
                return "\(key): \(value)"
            case .double(let value):
                return "\(key): \(value)"
            case .boolean(let value):
                return "\(key): \(value ? "Yes" : "No")"
            case .data:
                return nil
            }
        }
        return details.prefix(4).joined(separator: " • ")
    }

    func rehomedForPublicIDRepair(to herdPublicID: UUID) -> HerdSharingBridgeRecordSnapshot {
        guard attributes["herdPublicID"] != nil else { return self }
        var updatedAttributes = attributes
        updatedAttributes["herdPublicID"] = .string(herdPublicID.uuidString)
        return HerdSharingBridgeRecordSnapshot(
            entityName: entityName,
            publicID: publicID,
            sourceObjectURI: sourceObjectURI,
            attributes: updatedAttributes
        )
    }

    fileprivate func applyingPublicIDRepairCrossHerdResolution(
        repairedStep: HerdSharingBridgeStep,
        entityType: PublicIDRepairEntityType,
        retainedPublicID: UUID,
        replacementPublicID: UUID
    ) -> HerdSharingBridgeRecordSnapshot {
        var updatedPublicID = publicID
        var updatedAttributes = attributes
        var changed = false

        if entityName == repairedStep.coreDataEntityName,
           parsedPublicID == retainedPublicID {
            updatedPublicID = replacementPublicID.uuidString
            updatedAttributes["publicID"] = .string(replacementPublicID.uuidString)
            changed = true
        }

        for (name, value) in attributes where name != "publicID" {
            guard publicIDRepairReferencedEntityType(
                entityName: entityName,
                attributeName: name
            ) == entityType,
            case .string(let rawID) = value,
            UUID(uuidString: rawID) == retainedPublicID else {
                continue
            }
            updatedAttributes[name] = .string(replacementPublicID.uuidString)
            changed = true
        }

        guard changed else { return self }
        return HerdSharingBridgeRecordSnapshot(
            entityName: entityName,
            publicID: updatedPublicID,
            sourceObjectURI: sourceObjectURI,
            attributes: updatedAttributes
        )
    }

    fileprivate func replacingPublicIDForRepair(_ replacementPublicID: UUID)
        -> HerdSharingBridgeRecordSnapshot
    {
        var updatedAttributes = attributes
        updatedAttributes["publicID"] = .string(replacementPublicID.uuidString)
        return HerdSharingBridgeRecordSnapshot(
            entityName: entityName,
            publicID: replacementPublicID.uuidString,
            sourceObjectURI: sourceObjectURI,
            attributes: updatedAttributes
        )
    }
}

func publicIDRepairBridgeStep(
    for entityType: PublicIDRepairEntityType
) -> HerdSharingBridgeStep? {
    switch entityType {
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

func publicIDRepairEntityType(
    for step: HerdSharingBridgeStep
) -> PublicIDRepairEntityType? {
    PublicIDRepairEntityType.allCases.first {
        publicIDRepairBridgeStep(for: $0) == step
    }
}

/// Ownership partitioning intentionally resolves only parent relationships. General reference
/// translation uses `publicIDRepairReferencedEntityType` below and therefore still covers lookup
/// references without allowing them to determine a bridge-only record's Herd.
func publicIDRepairReferencedStep(
    entityName: String,
    attributeName: String
) -> HerdSharingBridgeStep? {
    publicIDRepairOwnershipBearingReferencedStep(
        entityName: entityName,
        attributeName: attributeName
    )
}

func publicIDRepairOwnershipBearingReferencedStep(
    entityName: String,
    attributeName: String
) -> HerdSharingBridgeStep? {
    switch (entityName, attributeName) {
    case (SharedAnimalTagRecord.entityName, "animalPublicID"),
         (SharedMovementRecord.entityName, "animalPublicID"),
         (SharedStatusRecord.entityName, "animalPublicID"),
         (SharedHealthRecord.entityName, "animalPublicID"),
         (SharedPregnancyCheckRecord.entityName, "animalPublicID"),
         (SharedWorkingQueueItemRecord.entityName, "animalPublicID"),
         (SharedWorkingTreatmentRecord.entityName, "animalPublicID"),
         (SharedFieldCheckAnimalCheckRecord.entityName, "animalPublicID"),
         (SharedFieldCheckAnimalCheckRecord.entityName, "animalIDSnapshot"),
         (SharedFieldCheckFindingRecord.entityName, "animalPublicID"),
         (SharedFieldCheckFindingRecord.entityName, "animalIDSnapshot"):
        return .animals
    case (SharedWorkingQueueItemRecord.entityName, "sessionPublicID"),
         (SharedWorkingTreatmentRecord.entityName, "sessionPublicID"):
        return .workingSessions
    case (SharedFieldCheckSessionRecord.entityName, "pasturePublicID"):
        return .pastures
    case (SharedFieldCheckAnimalCheckRecord.entityName, "sessionPublicID"),
         (SharedFieldCheckFindingRecord.entityName, "sessionPublicID"),
         (SharedFieldCheckFindingRecord.entityName, "sessionIDSnapshot"):
        return .fieldCheckSessions
    default:
        return nil
    }
}

func publicIDRepairReferencedEntityType(
    entityName: String,
    attributeName: String
) -> PublicIDRepairEntityType? {
    switch (entityName, attributeName) {
    case (SharedAnimalRecord.entityName, "tagColorID"):
        return .tagColorDefinition
    case (SharedAnimalRecord.entityName, "statusReferenceID"):
        return .animalStatusReference
    case (SharedAnimalRecord.entityName, "pasturePublicID"):
        return .pasture
    case (SharedAnimalRecord.entityName, "sireAnimalPublicID"),
         (SharedAnimalRecord.entityName, "damAnimalPublicID"):
        return .animal
    case (SharedAnimalTagRecord.entityName, "animalPublicID"):
        return .animal
    case (SharedAnimalTagRecord.entityName, "colorID"):
        return .tagColorDefinition
    case (SharedPastureRecord.entityName, "groupPublicID"):
        return .pastureGroup
    case (SharedMovementRecord.entityName, "animalPublicID"),
         (SharedStatusRecord.entityName, "animalPublicID"),
         (SharedHealthRecord.entityName, "animalPublicID"),
         (SharedPregnancyCheckRecord.entityName, "animalPublicID"):
        return .animal
    case (SharedStatusRecord.entityName, "oldStatusReferenceID"),
         (SharedStatusRecord.entityName, "newStatusReferenceID"):
        return .animalStatusReference
    case (SharedHealthRecord.entityName, "workingSessionPublicID"),
         (SharedPregnancyCheckRecord.entityName, "workingSessionPublicID"):
        return .workingSession
    case (SharedPregnancyCheckRecord.entityName, "sireAnimalPublicID"):
        return .animal
    case (SharedWorkingSessionRecord.entityName, "sourcePasturePublicID"):
        return .pasture
    case (SharedWorkingQueueItemRecord.entityName, "sessionPublicID"),
         (SharedWorkingTreatmentRecord.entityName, "sessionPublicID"):
        return .workingSession
    case (SharedWorkingQueueItemRecord.entityName, "animalPublicID"),
         (SharedWorkingTreatmentRecord.entityName, "animalPublicID"):
        return .animal
    case (SharedWorkingQueueItemRecord.entityName, "collectedFromPasturePublicID"),
         (SharedWorkingQueueItemRecord.entityName, "destinationPasturePublicID"):
        return .pasture
    case (SharedFieldCheckSessionRecord.entityName, "pasturePublicID"):
        return .pasture
    case (SharedFieldCheckAnimalCheckRecord.entityName, "sessionPublicID"),
         (SharedFieldCheckFindingRecord.entityName, "sessionPublicID"),
         (SharedFieldCheckFindingRecord.entityName, "sessionIDSnapshot"):
        return .fieldCheckSession
    case (SharedFieldCheckAnimalCheckRecord.entityName, "animalPublicID"),
         (SharedFieldCheckAnimalCheckRecord.entityName, "animalIDSnapshot"),
         (SharedFieldCheckFindingRecord.entityName, "animalPublicID"),
         (SharedFieldCheckFindingRecord.entityName, "animalIDSnapshot"):
        return .animal
    case (SharedFieldCheckAnimalCheckRecord.entityName, "rosterTagColorID"),
         (SharedFieldCheckAnimalCheckRecord.entityName, "damRosterTagColorID"),
         (SharedFieldCheckFindingRecord.entityName, "animalDisplayTagColorIDSnapshot"):
        return .tagColorDefinition
    default:
        return nil
    }
}
