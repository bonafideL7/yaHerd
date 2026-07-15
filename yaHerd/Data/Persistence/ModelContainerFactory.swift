//
//  ModelContainerFactory.swift
//  yaHerd
//

import Foundation
import SwiftData

enum ModelContainerFactory {
    static let storeName = "yaHerdStore"
    static let recoveryStoreName = "yaHerdRecoveryStore"
    static let cloudKitContainerIdentifier = "iCloud.ltd.yaherd"

    static var schema: Schema {
        Schema(versionedSchema: YaHerdMigrationPlan.currentSchema)
    }

    static func makeContainer(syncMode: SyncMode) throws -> ModelContainer {
        let schema = self.schema
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            cloudKitDatabase: cloudKitDatabase(for: syncMode)
        )

        return try makeContainer(
            schema: schema,
            configuration: configuration
        )
    }

    static func makeContainer(
        syncMode: SyncMode,
        storeURL: URL
    ) throws -> ModelContainer {
        let schema = self.schema
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: cloudKitDatabase(for: syncMode)
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
            isStoredInMemoryOnly: true
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

    private static func cloudKitDatabase(for syncMode: SyncMode) -> ModelConfiguration.CloudKitDatabase {
        switch syncMode {
        case .localOnly:
            .none
        case .iCloud:
            .private(cloudKitContainerIdentifier)
        }
    }
}
