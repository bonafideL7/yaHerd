import XCTest
@testable import yaHerd

@MainActor
final class ApplicationSettingsTests: XCTestCase {
    func testDefaultsAreTypedAndValidated() {
        let settings = ApplicationSettings(store: InMemoryApplicationSettingsStore())

        XCTAssertFalse(settings.isDashboardEnabled)
        XCTAssertTrue(settings.hardDeleteAnimals)
        XCTAssertEqual(settings.targetAcresPerHeadDefault, 3.0)
        XCTAssertEqual(settings.usableAcreagePercentDefault, 100)
        XCTAssertEqual(settings.recentPastureIDs, [])
        XCTAssertEqual(settings.homeDismissedSetupSuggestionIDs, [])
        XCTAssertTrue(settings.isHomeSetupSuggestionsExpanded)
    }

    func testLegacyKeysMigrateToCanonicalKeys() {
        let pastureID = UUID()
        let store = InMemoryApplicationSettingsStore(values: [
            "isDashboardEnabled": true,
            "hardDeleteAnimals": false,
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
        XCTAssertFalse(settings.hardDeleteAnimals)
        XCTAssertEqual(settings.targetAcresPerHeadDefault, 4.5)
        XCTAssertEqual(settings.usableAcreagePercentDefault, 85)
        XCTAssertEqual(settings.recentPastureIDs, [pastureID])
        XCTAssertEqual(settings.homeDismissedSetupSuggestionIDs, ["addFirstPasture"])
        XCTAssertFalse(settings.isHomeSetupSuggestionsExpanded)
        XCTAssertEqual(settings.legacyRecentPastureNames, ["North", "South"])

        XCTAssertNil(storedValues["isDashboardEnabled"])
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
        settings.homeDismissedSetupSuggestionIDs = [" addFirstPasture ", ""]

        XCTAssertEqual(settings.targetAcresPerHeadDefault, 0.25)
        XCTAssertEqual(settings.usableAcreagePercentDefault, 100)
        XCTAssertEqual(settings.recentPastureIDs, [firstID, secondID, thirdID, fourthID])
        XCTAssertEqual(settings.homeDismissedSetupSuggestionIDs, ["addFirstPasture"])

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

    func testResetToDefaultsRestoresLocalPreferences() {
        let settings = ApplicationSettings(store: InMemoryApplicationSettingsStore())
        settings.isDashboardEnabled = true
        settings.hardDeleteAnimals = false
        settings.targetAcresPerHeadDefault = 8.0
        settings.usableAcreagePercentDefault = 60
        settings.recentPastureIDs = [UUID()]
        settings.homeDismissedSetupSuggestionIDs = ["addFirstPasture"]
        settings.isHomeSetupSuggestionsExpanded = false

        settings.resetToDefaults()

        XCTAssertFalse(settings.isDashboardEnabled)
        XCTAssertTrue(settings.hardDeleteAnimals)
        XCTAssertEqual(settings.targetAcresPerHeadDefault, 3.0)
        XCTAssertEqual(settings.usableAcreagePercentDefault, 100)
        XCTAssertEqual(settings.recentPastureIDs, [])
        XCTAssertEqual(settings.homeDismissedSetupSuggestionIDs, [])
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
