//
//  YaHerdSchemaV1.swift
//  yaHerd
//

import SwiftData

/// The persistent model shipped with yaHerd 1.0.
///
/// Keep the model list and version identifier stable after release. Any persistent
/// model change must be introduced in a new `VersionedSchema` and connected through
/// `YaHerdMigrationPlan`.
enum YaHerdSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            Herd.self,
            Animal.self,
            AnimalTag.self,
            TagColorDefinition.self,
            AnimalStatusReference.self,
            Pasture.self,
            PastureGroup.self,
            HealthRecord.self,
            PregnancyCheck.self,
            MovementRecord.self,
            StatusRecord.self,
            WorkingSession.self,
            WorkingQueueItem.self,
            WorkingTreatmentRecord.self,
            WorkingProtocolTemplate.self,
            FieldCheckSession.self,
            FieldCheckAnimalCheck.self,
            FieldCheckFinding.self,
            CollaborationRevisionRecord.self
        ]
    }
}
