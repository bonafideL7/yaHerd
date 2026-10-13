//
//  YaHerdCurrentModels.swift
//  yaHerd
//

/// App-facing names for the models in the current persistent schema.
///
/// When a new schema version becomes current, update these aliases only after
/// its migration stage and fixture upgrade tests are complete.
typealias Herd = YaHerdSchemaV1.Herd
typealias Animal = YaHerdSchemaV1.Animal
typealias AnimalTag = YaHerdSchemaV1.AnimalTag
typealias TagColorDefinition = YaHerdSchemaV1.TagColorDefinition
typealias AnimalStatusReference = YaHerdSchemaV1.AnimalStatusReference
typealias Pasture = YaHerdSchemaV1.Pasture
typealias PastureGroup = YaHerdSchemaV1.PastureGroup
typealias HealthRecord = YaHerdSchemaV1.HealthRecord
typealias PregnancyCheck = YaHerdSchemaV1.PregnancyCheck
typealias MovementRecord = YaHerdSchemaV1.MovementRecord
typealias StatusRecord = YaHerdSchemaV1.StatusRecord
typealias WorkingSession = YaHerdSchemaV1.WorkingSession
typealias WorkingQueueItem = YaHerdSchemaV1.WorkingQueueItem
typealias WorkingTreatmentRecord = YaHerdSchemaV1.WorkingTreatmentRecord
typealias WorkingProtocolTemplate = YaHerdSchemaV1.WorkingProtocolTemplate
typealias FieldCheckSession = YaHerdSchemaV1.FieldCheckSession
typealias FieldCheckAnimalCheck = YaHerdSchemaV1.FieldCheckAnimalCheck
typealias FieldCheckFinding = YaHerdSchemaV1.FieldCheckFinding
