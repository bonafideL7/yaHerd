import Foundation

extension PublicIDRepairManifest {
    func appendingLocalRecoveryGeneration(
        completedAt: Date,
        backup: PublicIDRepairBackupReference,
        action: PublicIDRepairRecoveryChoice,
        validationPassed: Bool?
    ) -> PublicIDRepairManifest {
        let generation = PublicIDRepairManifestGeneration(
            number: currentGenerationNumber + 1,
            capturedAt: completedAt,
            backup: backup,
            recordMappings: recordMappings,
            referenceTransformations: referenceTransformations,
            selectedResolutionIDs: ["local-recovery|\(action.rawValue)"],
            bridgeRecoveryActions: bridgeRecoveryActions,
            validationPassed: validationPassed
        )
        return PublicIDRepairManifest(
            schemaVersion: schemaVersion,
            generations: generations + [generation]
        )
    }

    /// Persists a deliberate Diagnostics binding for an already-authoritative manifest identity.
    /// This generation changes no public ID and mutates no local data; it only records which
    /// current semantic record the user identified so the existing recovery planner can replay
    /// the original manifest mapping on its next pass.
    func appendingLocalRecoveryResolutionGeneration(
        completedAt: Date,
        selectedResolutionIDs: [String]
    ) -> PublicIDRepairManifest {
        guard !selectedResolutionIDs.isEmpty else { return self }
        let generation = PublicIDRepairManifestGeneration(
            number: currentGenerationNumber + 1,
            capturedAt: completedAt,
            backup: nil,
            recordMappings: recordMappings,
            referenceTransformations: referenceTransformations,
            selectedResolutionIDs: selectedResolutionIDs.sorted(),
            bridgeRecoveryActions: bridgeRecoveryActions,
            validationPassed: nil
        )
        return PublicIDRepairManifest(
            schemaVersion: schemaVersion,
            generations: generations + [generation]
        )
    }

    func appendingBridgeRecoveryDecision(
        completedAt: Date,
        action: PublicIDRepairBridgeRecoveryAction
    ) -> PublicIDRepairManifest {
        appendingBridgeDecisions(
            completedAt: completedAt,
            collisionResolutions: [],
            referenceUpdates: [],
            recoveryActions: [action]
        )
    }
}
