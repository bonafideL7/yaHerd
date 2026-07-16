import XCTest
@testable import yaHerd

@MainActor
final class ApplicationSettingsTests: XCTestCase {
    func testDefaultsAreTypedAndValidated() {
        let settings = ApplicationSettings(store: InMemoryApplicationSettingsStore())

        XCTAssertEqual(settings.syncMode, .localOnly)
        XCTAssertFalse(settings.allowHardDelete)
        XCTAssertFalse(settings.isDashboardEnabled)
        XCTAssertEqual(settings.targetAcresPerHeadDefault, 3.0)
        XCTAssertEqual(settings.usableAcreagePercentDefault, 100)
        XCTAssertEqual(settings.recentPastureIDs, [])
        XCTAssertEqual(settings.homeDismissedSetupSuggestionIDs, [])
        XCTAssertTrue(settings.isHomeSetupSuggestionsExpanded)
    }

    func testLegacyKeysMigrateToCanonicalKeys() {
        let pastureID = UUID()
        let store = InMemoryApplicationSettingsStore(values: [
            "syncMode": SyncMode.iCloud.rawValue,
            "allowHardDelete": true,
            "isDashboardEnabled": true,
            "targetAcresPerHeadDefault": 4.5,
            "usableAcreagePercentDefault": 85,
            "recentPastureIDs": pastureID.uuidString,
            "homeDismissedSetupSuggestionIDs": "addFirstPasture,reviewSyncSetup",
            "homeSetupSuggestionsExpanded": false,
            "recentPastureNames": "North|South",
        ])

        let settings = ApplicationSettings(store: store)
        let storedValues = store.snapshot()

        XCTAssertEqual(settings.syncMode, .iCloud)
        XCTAssertTrue(settings.allowHardDelete)
        XCTAssertTrue(settings.isDashboardEnabled)
        XCTAssertEqual(settings.targetAcresPerHeadDefault, 4.5)
        XCTAssertEqual(settings.usableAcreagePercentDefault, 85)
        XCTAssertEqual(settings.recentPastureIDs, [pastureID])
        XCTAssertEqual(
            settings.homeDismissedSetupSuggestionIDs,
            ["addFirstPasture", "reviewSyncSetup"]
        )
        XCTAssertFalse(settings.isHomeSetupSuggestionsExpanded)
        XCTAssertEqual(settings.legacyRecentPastureNames, ["North", "South"])

        XCTAssertEqual(
            storedValues[ApplicationSettingKey.syncMode.rawValue] as? String,
            SyncMode.iCloud.rawValue
        )
        XCTAssertNil(storedValues["syncMode"])
        XCTAssertNil(storedValues["allowHardDelete"])
        XCTAssertNil(storedValues["recentPastureNames"])
        XCTAssertEqual(
            storedValues[ApplicationSettingsCatalog.schemaVersionKey] as? Int,
            ApplicationSettingsCatalog.currentSchemaVersion
        )
    }

    func testInvalidValuesAreClampedAndNormalizedBeforePersistence() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let fourthID = UUID()
        let fifthID = UUID()
        let store = InMemoryApplicationSettingsStore()
        let settings = ApplicationSettings(store: store)

        settings.targetAcresPerHeadDefault = -10
        settings.usableAcreagePercentDefault = 250
        settings.recentPastureIDs = [firstID, firstID, secondID, thirdID, fourthID, fifthID]
        settings.homeDismissedSetupSuggestionIDs = [" addFirstPasture ", "", "reviewSyncSetup"]

        XCTAssertEqual(settings.targetAcresPerHeadDefault, 0.25)
        XCTAssertEqual(settings.usableAcreagePercentDefault, 100)
        XCTAssertEqual(settings.recentPastureIDs, [firstID, secondID, thirdID, fourthID])
        XCTAssertEqual(
            settings.homeDismissedSetupSuggestionIDs,
            ["addFirstPasture", "reviewSyncSetup"]
        )

        let storedValues = store.snapshot()
        XCTAssertEqual(
            storedValues[ApplicationSettingKey.targetAcresPerHeadDefault.rawValue] as? Double,
            0.25
        )
        XCTAssertEqual(
            storedValues[ApplicationSettingKey.usableAcreagePercentDefault.rawValue] as? Int,
            100
        )
        XCTAssertEqual(
            storedValues[ApplicationSettingKey.recentPastureIDs.rawValue] as? [String],
            [firstID, secondID, thirdID, fourthID].map(\.uuidString)
        )
    }

    func testScopeClassificationSeparatesDeviceStateFromSyncedPreferences() {
        XCTAssertEqual(
            Set(ApplicationSettingsCatalog.synchronizedKeys),
            [
                .allowHardDelete,
                .dashboardEnabled,
                .targetAcresPerHeadDefault,
                .usableAcreagePercentDefault,
                .homeDismissedSetupSuggestionIDs,
            ]
        )
        XCTAssertEqual(
            Set(ApplicationSettingsCatalog.localKeys),
            [
                .syncMode,
                .recentPastureIDs,
                .homeSetupSuggestionsExpanded,
                .legacyRecentPastureNames,
            ]
        )
    }

    func testSettingsEmitPersistenceUpdatesForSynchronization() {
        let settings = ApplicationSettings(store: InMemoryApplicationSettingsStore())
        var persistedKeys: [ApplicationSettingKey] = []

        settings.setPersistedChangeHandler { key in
            persistedKeys.append(key)
        }
        settings.isDashboardEnabled = true

        XCTAssertEqual(persistedKeys, [.dashboardEnabled])
    }

    func testInMemoryStoresAreIndependent() {
        let firstSettings = ApplicationSettings(store: InMemoryApplicationSettingsStore())
        let secondSettings = ApplicationSettings(store: InMemoryApplicationSettingsStore())

        firstSettings.allowHardDelete = true
        firstSettings.targetAcresPerHeadDefault = 7.5

        XCTAssertTrue(firstSettings.allowHardDelete)
        XCTAssertEqual(firstSettings.targetAcresPerHeadDefault, 7.5)
        XCTAssertFalse(secondSettings.allowHardDelete)
        XCTAssertEqual(secondSettings.targetAcresPerHeadDefault, 3.0)
    }
    func testSynchronizerUsesOnlySynchronizedCatalogKeys() {
        let recentPastureID = UUID()
        let settings = ApplicationSettings(store: InMemoryApplicationSettingsStore())
        settings.syncMode = .iCloud
        settings.allowHardDelete = true
        settings.recentPastureIDs = [recentPastureID]

        let cloudStore = InMemoryApplicationSettingsCloudStore(values: [
            "isDashboardEnabled": true,
            "recentPastureNames": "North",
        ])
        let synchronizer = AppSettingsSynchronizer(
            settings: settings,
            cloudStore: cloudStore,
            keys: ApplicationSettingsCatalog.synchronizedKeys
        )

        synchronizer.startIfNeeded(syncMode: .iCloud)

        XCTAssertTrue(settings.isDashboardEnabled)
        XCTAssertEqual(
            cloudStore.snapshot()[ApplicationSettingKey.allowHardDelete.rawValue] as? Bool,
            true
        )
        XCTAssertNil(cloudStore.snapshot()[ApplicationSettingKey.syncMode.rawValue])
        XCTAssertNil(cloudStore.snapshot()[ApplicationSettingKey.recentPastureIDs.rawValue])
        XCTAssertNil(cloudStore.snapshot()["recentPastureNames"])

        settings.allowHardDelete = false
        settings.recentPastureIDs = [UUID()]

        XCTAssertEqual(
            cloudStore.snapshot()[ApplicationSettingKey.allowHardDelete.rawValue] as? Bool,
            false
        )
        XCTAssertNil(cloudStore.snapshot()[ApplicationSettingKey.recentPastureIDs.rawValue])
        synchronizer.stop()
    }

    func testDeleteCloudSettingsRemovesCanonicalLegacyAndMigrationKeys() {
        let settings = ApplicationSettings(store: InMemoryApplicationSettingsStore())
        let cloudStore = InMemoryApplicationSettingsCloudStore(values: [
            ApplicationSettingKey.allowHardDelete.rawValue: true,
            "isDashboardEnabled": true,
            "recentPastureNames": "North",
            ApplicationSettingsCatalog.schemaVersionKey: 1,
        ])
        let synchronizer = AppSettingsSynchronizer(
            settings: settings,
            cloudStore: cloudStore,
            keys: ApplicationSettingsCatalog.synchronizedKeys
        )

        let deletedCount = synchronizer.deleteCloudSettings()

        XCTAssertEqual(deletedCount, 4)
        XCTAssertTrue(cloudStore.snapshot().isEmpty)
    }

}
