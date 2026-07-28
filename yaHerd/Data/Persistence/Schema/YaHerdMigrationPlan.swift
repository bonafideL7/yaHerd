//
//  YaHerdMigrationPlan.swift
//  yaHerd
//

import SwiftData

/// The ordered history of every SwiftData schema released by yaHerd.
///
/// `YaHerdSchemaV1` is still the current unreleased schema. Persistent-model
/// changes made before the first production release update V1, its sharing
/// bridge, its disk fixture, and its tests together. After V1 ships, it becomes
/// immutable and every persistent-model change must add a new schema and stage.
enum YaHerdMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [YaHerdSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }

    static var currentSchema: any VersionedSchema.Type {
        guard let currentSchema = schemas.last else {
            preconditionFailure("YaHerdMigrationPlan must contain at least one schema.")
        }
        return currentSchema
    }
}
