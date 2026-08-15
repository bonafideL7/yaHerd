import Foundation

private enum PublicIDRepairLegacyCollisionCodingKeys: String, CodingKey {
    case entityType
    case retainedPublicID
    case selectedHerdPublicID
    case herdPublicIDs
    case replacementMappings
}

extension PublicIDRepairBridgeCollisionResolution {
    /// Existing v3 journals may predate durable `replacementMappings`. Decode that exact legacy
    /// state using the legacy deterministic rule once, then every newly encoded report persists
    /// the resulting IDs in the manifest. Normal repair and bridge replay never call this path.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: PublicIDRepairLegacyCollisionCodingKeys.self
        )
        let decodedEntityType = try container.decode(
            PublicIDRepairEntityType.self,
            forKey: .entityType
        )
        let decodedRetainedPublicID = try container.decode(
            UUID.self,
            forKey: .retainedPublicID
        )
        let decodedSelectedHerdPublicID = try container.decode(
            UUID.self,
            forKey: .selectedHerdPublicID
        )
        let decodedHerdPublicIDs = Array(
            Set(try container.decode([UUID].self, forKey: .herdPublicIDs))
        ).sorted { $0.uuidString < $1.uuidString }

        let decodedMappings: [PublicIDRepairBridgeReplacementMapping]?
        if let persisted = try container.decodeIfPresent(
            [PublicIDRepairBridgeReplacementMapping].self,
            forKey: .replacementMappings
        ) {
            let participants = Set(decodedHerdPublicIDs)
            let filtered = persisted.filter {
                participants.contains($0.herdPublicID)
                    && $0.herdPublicID != decodedSelectedHerdPublicID
            }.sorted { $0.herdPublicID.uuidString < $1.herdPublicID.uuidString }
            decodedMappings = filtered.isEmpty ? nil : filtered
        } else {
            let migrated = decodedHerdPublicIDs.compactMap { herdPublicID
                -> PublicIDRepairBridgeReplacementMapping? in
                guard herdPublicID != decodedSelectedHerdPublicID else { return nil }
                return PublicIDRepairBridgeReplacementMapping(
                    herdPublicID: herdPublicID,
                    replacementPublicID: publicIDRepairLegacyV3CrossHerdReplacementID(
                        entityType: decodedEntityType,
                        originalPublicID: decodedRetainedPublicID,
                        herdPublicID: herdPublicID
                    )
                )
            }
            decodedMappings = migrated.isEmpty ? nil : migrated
        }

        entityType = decodedEntityType
        retainedPublicID = decodedRetainedPublicID
        selectedHerdPublicID = decodedSelectedHerdPublicID
        herdPublicIDs = decodedHerdPublicIDs
        replacementMappings = decodedMappings
    }
}
