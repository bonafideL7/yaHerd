//
//  ModelContainerFactory.swift
//  yaHerd
//

import Foundation
import SwiftData

enum ModelContainerFactory {
    static let storeName = "yaHerdStore"
    static let recoveryStoreName = "yaHerdRecoveryStore"

    static var schema: Schema {
        Schema(versionedSchema: YaHerdMigrationPlan.currentSchema)
    }

    static func makeContainer() throws -> ModelContainer {
        let schema = self.schema
        let configuration = ModelConfiguration(
            storeName,
            schema: schema
        )

        return try makeContainer(
            schema: schema,
            configuration: configuration
        )
    }

    static func makeContainer(storeURL: URL) throws -> ModelContainer {
        let schema = self.schema
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            url: storeURL,
            allowsSave: true
        )

        return try makeContainer(
            schema: schema,
            configuration: configuration
        )
    }

    static func makeRecoveryContainer() throws -> ModelContainer {
        let schema = self.schema
        let fallbackConfiguration = ModelConfiguration(
            recoveryStoreName,
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: false
        )

        return try makeContainer(
            schema: schema,
            configuration: fallbackConfiguration
        )
    }

    private static func makeContainer(
        schema: Schema,
        configuration: ModelConfiguration
    ) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: YaHerdMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
