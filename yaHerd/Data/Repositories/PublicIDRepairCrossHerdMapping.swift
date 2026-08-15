import Foundation

/// Legacy transport IDs used only to feed an already-durable manifest choice into the existing
/// local repair planner while pending v3 journals remain supported. These directives never choose
/// canonical records or generate replacement IDs.
enum PublicIDRepairCrossHerdDirective {
    private static let prefix = "yaHerd-public-id-repair-cross-herd"

    static func ownerResolutionID(
        entityType: PublicIDRepairEntityType,
        retainedPublicID: UUID
    ) -> String {
        [
            prefix,
            "owner",
            entityType.rawValue,
            retainedPublicID.uuidString.lowercased(),
        ].joined(separator: "|")
    }

    static func replacementResolutionID(
        entityType: PublicIDRepairEntityType,
        retainedPublicID: UUID,
        herdPublicID: UUID
    ) -> String {
        [
            prefix,
            "replacement",
            entityType.rawValue,
            retainedPublicID.uuidString.lowercased(),
            herdPublicID.uuidString.lowercased(),
        ].joined(separator: "|")
    }
}

func publicIDRepairCrossHerdReplacementID(
    entityType: PublicIDRepairEntityType,
    retainedPublicID: UUID,
    herdPublicID: UUID
) -> UUID {
    publicIDRepairDeterministicReplacementID(
        entityType: entityType,
        originalPublicID: retainedPublicID,
        portableRecordIdentity: publicIDRepairManifestCrossHerdRecordIdentity(
            entityType: entityType,
            originalPublicID: retainedPublicID,
            herdPublicID: herdPublicID
        )
    )
}

func makePublicIDRepairBridgeCollisionResolution(
    entityType: PublicIDRepairEntityType,
    retainedPublicID: UUID,
    selectedHerdPublicID: UUID,
    herdPublicIDs: [UUID],
    existingMappings: [PublicIDRepairBridgeReplacementMapping] = []
) -> PublicIDRepairBridgeCollisionResolution {
    PublicIDRepairBridgeCollisionResolution(
        entityType: entityType,
        retainedPublicID: retainedPublicID,
        selectedHerdPublicID: selectedHerdPublicID,
        herdPublicIDs: herdPublicIDs,
        replacementMappings: existingMappings
    )
}

extension PublicIDRepairBridgeCollisionResolution {
    func replacementPublicID(for herdPublicID: UUID) -> UUID? {
        guard herdPublicIDs.contains(herdPublicID),
              herdPublicID != selectedHerdPublicID else {
            return nil
        }
        return authoritativeReplacementMappings.first {
            $0.herdPublicID == herdPublicID
        }?.replacementPublicID
    }

    var workerResolutionDirectives: [PublicIDRepairReferenceResolution] {
        var directives = [
            PublicIDRepairReferenceResolution(
                unresolvedReferenceID: PublicIDRepairCrossHerdDirective.ownerResolutionID(
                    entityType: entityType,
                    retainedPublicID: retainedPublicID
                ),
                selectedCandidateStableRecordIdentifier: selectedHerdPublicID.uuidString.lowercased()
            )
        ]
        directives.append(contentsOf: authoritativeReplacementMappings.map { mapping in
            PublicIDRepairReferenceResolution(
                unresolvedReferenceID: PublicIDRepairCrossHerdDirective.replacementResolutionID(
                    entityType: entityType,
                    retainedPublicID: retainedPublicID,
                    herdPublicID: mapping.herdPublicID
                ),
                selectedCandidateStableRecordIdentifier: mapping.replacementPublicID.uuidString.lowercased()
            )
        })
        return directives.sorted { $0.id < $1.id }
    }
}
