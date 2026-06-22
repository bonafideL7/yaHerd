//
//  ModelContainerFactory.swift
//  yaHerd
//

import SwiftData

enum ModelContainerFactory {
    static let storeName = "yaHerdStore"
    static let recoveryStoreName = "yaHerdRecoveryStore"
    static let cloudKitContainerIdentifier = "iCloud.ltd.yaherd"

    static func makeContainer(
        schema: Schema,
        syncMode: SyncMode
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            cloudKitDatabase: cloudKitDatabase(for: syncMode)
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    static func makeRecoveryContainer(schema: Schema) throws -> ModelContainer {
        let fallbackConfiguration = ModelConfiguration(
            recoveryStoreName,
            schema: schema,
            isStoredInMemoryOnly: true
        )

        return try ModelContainer(
            for: schema,
            configurations: [fallbackConfiguration]
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
