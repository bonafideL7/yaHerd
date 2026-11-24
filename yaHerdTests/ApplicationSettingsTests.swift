import XCTest
@testable import yaHerd

@MainActor
final class ApplicationSettingsTests: XCTestCase {
    func testDefaultsAreTypedAndValidated() {
        let herdID = UUID()
        let settings = ApplicationSettings(store: InMemoryApplicationSettingsStore())

        XCTAssertFalse(settings.isDashboardEnabled)
        XCTAssertFalse(settings.hardDeleteAnimals)
        XCTAssertEqual(settings.targetAcresPerHeadDefault, 3.0)
        XCTAssertEqual(settings.usableAcreagePercentDefault, 100)
        XCTAssertEqual(settings.recentPastureIDs(for: herdID), [])
        XCTAssertEqual(settings.dismissedHomeSetupSuggestionIDs(for: herdID), [])
        XCTAssertTrue(settings.isHomeSetupSuggestionsExpanded)
    }

    func testLegacyKeysMigrateToCanonicalKeys() {
        let herdID = UUID()
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
        // Unscoped legacy record preferences cannot identify their owning Herd.
        XCTAssertEqual(settings.recentPastureIDs(for: herdID), [])
        XCTAssertEqual(settings.dismissedHomeSetupSuggestionIDs(for: herdID), [])
        XCTAssertEqual(storedValues[ApplicationSettingKey.recentPastureIDs.rawValue] as? [String: [String]], [:])
        XCTAssertEqual(storedValues[ApplicationSettingKey.homeDismissedSetupSuggestionIDs.rawValue] as? [String: [String]], [:])
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
        let herdID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let fourthID = UUID()
        let fifthID = UUID()
        let store = InMemoryApplicationSettingsStore()
        let settings = ApplicationSettings(store: store)

        settings.targetAcresPerHeadDefault = -10
        settings.usableAcreagePercentDefault = 250
        settings.setRecentPastureIDs([firstID, firstID, secondID, thirdID, fourthID, fifthID], for: herdID)
        settings.setDismissedHomeSetupSuggestionIDs([" addFirstPasture ", ""], for: herdID)

        XCTAssertEqual(settings.targetAcresPerHeadDefault, 0.25)
        XCTAssertEqual(settings.usableAcreagePercentDefault, 100)
        XCTAssertEqual(settings.recentPastureIDs(for: herdID), [firstID, secondID, thirdID, fourthID])
        XCTAssertEqual(settings.dismissedHomeSetupSuggestionIDs(for: herdID), ["addFirstPasture"])

        let otherHerdID = UUID()
        XCTAssertEqual(settings.recentPastureIDs(for: otherHerdID), [])
        XCTAssertEqual(settings.dismissedHomeSetupSuggestionIDs(for: otherHerdID), [])

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
        XCTAssertEqual(
            storedValues[ApplicationSettingKey.homeDismissedSetupSuggestionIDs.rawValue] as? [String: [String]],
            [herdID.uuidString: ["addFirstPasture"]]
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
        let herdID = UUID()
        let settings = ApplicationSettings(store: InMemoryApplicationSettingsStore())
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
