import Foundation

extension PublicIDRepairManifest {
    /// Backward-compatible local/report projection. The manifest remains the source of truth; these
    /// values exist so older orchestration and bridge translation call sites can be migrated
    /// incrementally without maintaining a second identity decision store.
    var reportReplacements: [PublicIDRepairReplacement] {
        let mappings = recordMappings.filter {
            !$0.retainedOriginalID && $0.origin != .bridgeCollision
        }
        return mappings.map { mapping in
            let retained = recordMappings.first {
                $0.entityType == mapping.entityType
                    && $0.originalPublicID == mapping.originalPublicID
                    && $0.retainedOriginalID
                    && $0.origin != .bridgeCollision
            }
            return PublicIDRepairReplacement(
                entityType: mapping.entityType,
                recordDescription: mapping.recordDescription,
                stableRecordIdentifier: mapping.portableRecordIdentity,
                retainedPublicID: mapping.originalPublicID,
                replacementPublicID: mapping.finalPublicID,
                owningHerdPublicID: mapping.owningHerdPublicID,
                recordFingerprint: mapping.recordFingerprint,
                retainedStableRecordIdentifier: retained?.portableRecordIdentity,
                retainedOwningHerdPublicID: retained?.owningHerdPublicID,
                retainedRecordFingerprint: retained?.recordFingerprint
            )
        }.sorted { $0.id < $1.id }
    }

    var reportReferenceUpdates: [PublicIDRepairReferenceUpdate] {
        referenceTransformations.compactMap { transformation in
            guard let entityType = transformation.sourceEntityType,
                  transformation.kind != .deletionTarget,
                  transformation.origin != .bridgeCollision else {
                return nil
            }
            return PublicIDRepairReferenceUpdate(
                entityType: entityType,
                recordDescription: transformation.sourcePortableRecordIdentity,
                stableRecordIdentifier: transformation.sourcePortableRecordIdentity,
                fieldName: transformation.fieldName,
                previousPublicID: transformation.previousPublicID,
                repairedPublicID: transformation.finalPublicID,
                owningHerdPublicID: transformation.owningHerdPublicID
            )
        }.sorted { $0.id < $1.id }
    }

    var reportBridgeCollisionResolutions: [PublicIDRepairBridgeCollisionResolution] {
        let collisionMappings = recordMappings.filter { $0.origin == .bridgeCollision }
        let grouped = Dictionary(grouping: collisionMappings) {
            "\($0.entityType.rawValue)|\($0.originalPublicID.uuidString.lowercased())"
        }
        return grouped.compactMap { _, mappings in
            let retained = mappings.filter {
                $0.retainedOriginalID && $0.finalPublicID == $0.originalPublicID
            }
            guard retained.count == 1,
                  let selectedOwner = retained[0].owningHerdPublicID else {
                return nil
            }
            let replacements = mappings.compactMap { mapping
                -> PublicIDRepairBridgeReplacementMapping? in
                guard !mapping.retainedOriginalID,
                      let owner = mapping.owningHerdPublicID else {
                    return nil
                }
                return PublicIDRepairBridgeReplacementMapping(
                    herdPublicID: owner,
                    replacementPublicID: mapping.finalPublicID
                )
            }
            let participantIDs = [selectedOwner] + replacements.map(\.herdPublicID)
            return PublicIDRepairBridgeCollisionResolution(
                entityType: retained[0].entityType,
                retainedPublicID: retained[0].originalPublicID,
                selectedHerdPublicID: selectedOwner,
                herdPublicIDs: participantIDs,
                replacementMappings: replacements
            )
        }.sorted { $0.id < $1.id }
    }
}
