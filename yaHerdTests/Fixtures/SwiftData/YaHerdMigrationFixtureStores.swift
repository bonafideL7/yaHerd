import Foundation
import SwiftData
@testable import yaHerd

@MainActor
enum YaHerdMigrationFixtureStores {
    static var versionIdentifiers: [Schema.Version] {
        [YaHerdSchemaV1FixtureStore.versionIdentifier]
    }

    static func createStore(
        for versionIdentifier: Schema.Version,
        at storeURL: URL
    ) throws {
        if versionIdentifier == YaHerdSchemaV1FixtureStore.versionIdentifier {
            try YaHerdSchemaV1FixtureStore.create(at: storeURL)
            return
        }

        throw FixtureRegistryError.missingFixture(versionIdentifier)
    }

    static func validateStoreOpenedThroughCurrentPlan(
        from versionIdentifier: Schema.Version,
        in context: ModelContext
    ) throws {
        if versionIdentifier == YaHerdSchemaV1FixtureStore.versionIdentifier {
            try YaHerdSchemaV1FixtureStore.validate(in: context)
            return
        }

        throw FixtureRegistryError.missingValidation(versionIdentifier)
    }
}

private enum FixtureRegistryError: Error {
    case missingFixture(Schema.Version)
    case missingValidation(Schema.Version)
}
