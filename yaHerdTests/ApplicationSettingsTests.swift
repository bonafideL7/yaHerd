import XCTest
@testable import yaHerd

@MainActor
final class ApplicationSettingsTests: XCTestCase {
    func testDefaultsAreTypedAndValidated() {
        let settings = ApplicationSettings(store: InMemoryApplicationSettingsStore())

        XCTAssertFalse(settings.isDashboardEnabled)
        XCTAssertFalse(settings.hardDeleteAnimals)
        XCTAssertEqual(settings.targetAcresPerHeadDefault, 3.0)
        XCTAssertEqual(settings.usableAcreagePercentDefault, 100)
        XCTAssertEqual(settings.recentPastureIDs(for: UUID()), [])
        XCTAssertEqual(settings.dismissedHomeSetupSuggestionIDs(for: UUID()), [])
        XCTAssertTrue(settings.isHomeSetupSuggestionsExpanded)
    }

    func testLegacyKeysMigrateToCanonicalKeys() {
        let pastureID = UUID()
        let store = InMemoryApplicationSettingsStore(values: [
            "isDashboardEnabled": true,
            "targetAcresPerHeadDefault": 4.5,
            "usableAcreagePercentDefault": 85,
            "recentPastureIDs": pastureID.uuidString,
            "homeDismissedSetupSuggestionIDs": "addFirstPasture",
            "homeSetupSuggestionsExpanded": false,
            "recentPastureNames": "North|South",
        ])

        let settings = ApplicationSettings(store: store)
        let storedValues = store.snapshot()

        XCTAssertTrue(settings.isDashboardEnabled)
        XCTAssertEqual(settings.targetAcresPerHeadDefault, 4.5)
        XCTAssertEqual(settings.usableAcreagePercentDefault, 85)
        // An unscoped legacy preference cannot be assigned to an arbitrary Herd.
        XCTAssertEqual(settings.recentPastureIDs(for: UUID()), [])
        XCTAssertEqual(settings.dismissedHomeSetupSuggestionIDs(for: UUID()), [])
        // Legacy device-wide dismissals cannot be attributed to a particular Herd.
        XCTAssertFalse(settings.isHomeSetupSuggestionsExpanded)
        XCTAssertEqual(settings.legacyRecentPastureNames, ["North", "South"])

        XCTAssertNil(storedValues["isDashboardEnabled"])
        XCTAssertNil(storedValues["recentPastureNames"])
        XCTAssertNil(storedValues["recentPastureIDs"])
        XCTAssertEqual(
            storedValues[ApplicationSettingKey.recentPastureIDs.rawValue] as? [String: [String]],
            [:]
        )
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
        let herdID = UUID()
        let store = InMemoryApplicationSettingsStore()
        let settings = ApplicationSettings(store: store)

        settings.targetAcresPerHeadDefault = -10
        settings.usableAcreagePercentDefault = 250
        settings.setRecentPastureIDs(
            [firstID, firstID, secondID, thirdID, fourthID, fifthID],
            for: herdID
        )
        settings.setDismissedHomeSetupSuggestionIDs([" addFirstPasture ", ""], for: herdID)

        XCTAssertEqual(settings.targetAcresPerHeadDefault, 0.25)
        XCTAssertEqual(settings.usableAcreagePercentDefault, 100)
        XCTAssertEqual(
            settings.recentPastureIDs(for: herdID),
            [firstID, secondID, thirdID, fourthID]
        )
        XCTAssertEqual(settings.dismissedHomeSetupSuggestionIDs(for: herdID), ["addFirstPasture"])

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
            storedValues[ApplicationSettingKey.recentPastureIDs.rawValue] as? [String: [String]],
            [herdID.uuidString: [firstID, secondID, thirdID, fourthID].map(\.uuidString)]
        )
    }

    func testInMemoryStoresAreIndependent() {
        let firstSettings = ApplicationSettings(store: InMemoryApplicationSettingsStore())
        let secondSettings = ApplicationSettings(store: InMemoryApplicationSettingsStore())

        firstSettings.isDashboardEnabled = true
        firstSettings.targetAcresPerHeadDefault = 7.5

        XCTAssertTrue(firstSettings.isDashboardEnabled)
        XCTAssertEqual(firstSettings.targetAcresPerHeadDefault, 7.5)
        XCTAssertFalse(secondSettings.isDashboardEnabled)
        XCTAssertEqual(secondSettings.targetAcresPerHeadDefault, 3.0)
    }

    func testRecentPasturesAreScopedByHerdAndRetainedAfterReload() {
        let store = InMemoryApplicationSettingsStore()
        let settings = ApplicationSettings(store: store)
        let firstHerdID = UUID()
        let secondHerdID = UUID()
        // UUIDs can legitimately recur in independent Herd scopes.
        let pastureID = UUID()

        settings.setRecentPastureIDs([pastureID], for: firstHerdID)
        XCTAssertEqual(settings.recentPastureIDs(for: firstHerdID), [pastureID])
        XCTAssertEqual(settings.recentPastureIDs(for: secondHerdID), [])

        settings.setRecentPastureIDs([pastureID], for: secondHerdID)
        settings.setRecentPastureIDs([], for: firstHerdID)
        XCTAssertEqual(settings.recentPastureIDs(for: firstHerdID), [])
        XCTAssertEqual(settings.recentPastureIDs(for: secondHerdID), [pastureID])

        let reloaded = ApplicationSettings(store: store)
        XCTAssertEqual(reloaded.recentPastureIDs(for: firstHerdID), [])
        XCTAssertEqual(reloaded.recentPastureIDs(for: secondHerdID), [pastureID])
    }

    func testHerdRecentPasturesNormalizeAndResetAllScopes() {
        let store = InMemoryApplicationSettingsStore()
        let settings = ApplicationSettings(store: store)
        let firstHerdID = UUID()
        let secondHerdID = UUID()
        let ids = (0..<5).map { _ in UUID() }

        settings.setRecentPastureIDs([ids[0], ids[0]] + Array(ids.dropFirst()), for: firstHerdID)
        settings.setRecentPastureIDs([ids[4]], for: secondHerdID)
        XCTAssertEqual(settings.recentPastureIDs(for: firstHerdID), Array(ids.prefix(4)))
        XCTAssertEqual(settings.recentPastureIDs(for: secondHerdID), [ids[4]])

        settings.resetToDefaults()
        XCTAssertEqual(settings.recentPastureIDs(for: firstHerdID), [])
        XCTAssertEqual(settings.recentPastureIDs(for: secondHerdID), [])
        let reloaded = ApplicationSettings(store: store)
        XCTAssertEqual(reloaded.recentPastureIDs(for: firstHerdID), [])
        XCTAssertEqual(reloaded.recentPastureIDs(for: secondHerdID), [])
    }

    func testDismissedSetupSuggestionsRemainScopedAcrossHerdSwitchesAndReload() {
        let store = InMemoryApplicationSettingsStore()
        let settings = ApplicationSettings(store: store)
        let firstHerdID = UUID()
        let secondHerdID = UUID()

        settings.setDismissedHomeSetupSuggestionIDs(["addFirstAnimal"], for: firstHerdID)
        XCTAssertEqual(settings.dismissedHomeSetupSuggestionIDs(for: firstHerdID), ["addFirstAnimal"])
        XCTAssertEqual(settings.dismissedHomeSetupSuggestionIDs(for: secondHerdID), [])

        settings.setDismissedHomeSetupSuggestionIDs(["addFirstPasture"], for: secondHerdID)
        settings.setDismissedHomeSetupSuggestionIDs([], for: firstHerdID)

        let reloaded = ApplicationSettings(store: store)
        XCTAssertEqual(reloaded.dismissedHomeSetupSuggestionIDs(for: firstHerdID), [])
        XCTAssertEqual(reloaded.dismissedHomeSetupSuggestionIDs(for: secondHerdID), ["addFirstPasture"])
        XCTAssertEqual(
            store.snapshot()[ApplicationSettingKey.homeDismissedSetupSuggestionIDs.rawValue] as? [String: [String]],
            [secondHerdID.uuidString: ["addFirstPasture"]]
        )
    }

    func testUnscopedLegacySetupDismissalsDoNotSuppressAnotherHerd() {
        let store = InMemoryApplicationSettingsStore(values: [
            ApplicationSettingKey.homeDismissedSetupSuggestionIDs.rawValue: ["addFirstAnimal"]
        ])
        let settings = ApplicationSettings(store: store)
        XCTAssertEqual(settings.dismissedHomeSetupSuggestionIDs(for: UUID()), [])
        XCTAssertEqual(
            store.snapshot()[ApplicationSettingKey.homeDismissedSetupSuggestionIDs.rawValue] as? [String: [String]],
            [:]
        )
    }

    func testResetToDefaultsRestoresLocalPreferences() {
        let settings = ApplicationSettings(store: InMemoryApplicationSettingsStore())
        let herdID = UUID()
        settings.isDashboardEnabled = true
        settings.hardDeleteAnimals = false
        settings.targetAcresPerHeadDefault = 8.0
        settings.usableAcreagePercentDefault = 60
        settings.setRecentPastureIDs([UUID()], for: herdID)
        settings.setDismissedHomeSetupSuggestionIDs(["addFirstPasture"], for: herdID)
        settings.isHomeSetupSuggestionsExpanded = false

        settings.resetToDefaults()

        XCTAssertFalse(settings.isDashboardEnabled)
        XCTAssertFalse(settings.hardDeleteAnimals)
        XCTAssertEqual(settings.targetAcresPerHeadDefault, 3.0)
        XCTAssertEqual(settings.usableAcreagePercentDefault, 100)
        XCTAssertEqual(settings.recentPastureIDs(for: herdID), [])
        XCTAssertEqual(settings.dismissedHomeSetupSuggestionIDs(for: herdID), [])
        XCTAssertTrue(settings.isHomeSetupSuggestionsExpanded)
    }
}

@MainActor
private final class InMemoryApplicationSettingsStore: ApplicationSettingsStore {
    private var values: [String: Any]

    init(values: [String: Any] = [:]) {
        self.values = values
    }

    func object(forKey key: String) -> Any? {
        values[key]
    }

    func set(_ value: Any, forKey key: String) {
        values[key] = value
    }

    func removeObject(forKey key: String) {
        values.removeValue(forKey: key)
    }

    func snapshot() -> [String: Any] {
        values
    }
}
