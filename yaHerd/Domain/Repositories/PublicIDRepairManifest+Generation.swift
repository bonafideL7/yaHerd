import Foundation

extension PublicIDRepairManifest {
    /// Appends one locally committed repair generation without flattening earlier identity
    /// decisions. The newly committed repair's current manifest state is recorded as the next
    /// generation; repeated identical mappings are allowed, while any changed final ID or owner
    /// remains visible to `contradictions` and therefore fails closed.
    func appendingCommittedRepair(
        _ latest: PublicIDRepairManifest
    ) -> PublicIDRepairManifest {
        guard let source = latest.generations.last else { return self }
        let generation = PublicIDRepairManifestGeneration(
            number: currentGenerationNumber + 1,
            capturedAt: source.capturedAt,
            backup: source.backup,
            recordMappings: latest.recordMappings,
            referenceTransformations: latest.referenceTransformations,
            selectedResolutionIDs: source.selectedResolutionIDs,
            bridgeRecoveryActions: latest.bridgeRecoveryActions,
            validationPassed: source.validationPassed
        )
        return PublicIDRepairManifest(
            schemaVersion: max(schemaVersion, latest.schemaVersion),
            generations: generations + [generation]
        )
    }

    /// Extends the manifest with a durable Diagnostics/bridge decision before any bridge mutation.
    /// Decision generations do not create a local backup because they do not mutate SwiftData.
    func appendingBridgeDecisions(
        completedAt: Date,
        collisionResolutions: [PublicIDRepairBridgeCollisionResolution],
        referenceUpdates: [PublicIDRepairReferenceUpdate],
        recoveryActions: [PublicIDRepairBridgeRecoveryAction]
    ) -> PublicIDRepairManifest {
        guard !collisionResolutions.isEmpty
                || !referenceUpdates.isEmpty
                || !recoveryActions.isEmpty else {
            return self
        }

        let currentBackup = generations.reversed().compactMap(\.backup).first
            ?? PublicIDRepairBackupReference(filename: "", path: "")
        let delta = PublicIDRepairManifest.migratingLegacy(
            completedAt: completedAt,
            replacements: [],
            referenceUpdates: referenceUpdates,
            backupFilename: currentBackup.filename,
            backupPath: currentBackup.path,
            validationPassed: true,
            bridgeCollisionResolutions: collisionResolutions,
            priorBackups: nil,
            bridgeRecoveryActions: recoveryActions
        )
        guard let source = delta.generations.last else { return self }
        let generation = PublicIDRepairManifestGeneration(
            number: currentGenerationNumber + 1,
            capturedAt: completedAt,
            backup: nil,
            recordMappings: source.recordMappings,
            referenceTransformations: source.referenceTransformations,
            selectedResolutionIDs: source.selectedResolutionIDs,
            bridgeRecoveryActions: source.bridgeRecoveryActions,
            validationPassed: nil
        )
        return PublicIDRepairManifest(
            schemaVersion: max(schemaVersion, delta.schemaVersion),
            generations: generations + [generation]
        )
    }

    var backupReferences: [PublicIDRepairBackupReference] {
        var byPath: [String: PublicIDRepairBackupReference] = [:]
        for backup in generations.compactMap(\.backup) where !backup.path.isEmpty {
            byPath[backup.path] = backup
        }
        return byPath.values.sorted { $0.path < $1.path }
    }
}
