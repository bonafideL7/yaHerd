//
//  YaHerdSchemaV1.swift
//  yaHerd
//

import SwiftData

/// Legacy SwiftData model declarations retained only while remaining
/// SwiftData-only model and seed source is retired. Neither the app nor its
/// tests create a SwiftData model container after the M10 runtime cutover.
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
            FieldCheckFinding.self
        ]
    }
}
