//
//  YaHerdMigrationPlan.swift
//  yaHerd
//

import SwiftData

/// The ordered history of every SwiftData schema released by yaHerd.
///
/// V1 is the initial release, so there is no migration stage yet. Add one schema,
/// one fixture store, and one stage for each future persistent-model release.
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
