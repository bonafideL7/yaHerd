import Foundation
import Observation

@MainActor
@Observable
final class ApplicationSettings {
    nonisolated static let defaultTargetAcresPerHead = 3.0
    nonisolated static let defaultUsableAcreagePercent = 100
    nonisolated static let targetAcresPerHeadRange = 0.25...25.0
    nonisolated static let usableAcreagePercentRange = 10...100
    nonisolated static let maximumRecentPastures = 4

    @ObservationIgnored private let store: any ApplicationSettingsStore
    @ObservationIgnored private var persistedChangeHandler: (@MainActor (ApplicationSettingKey) -> Void)?

    private var syncModeValue: SyncMode
    private var allowHardDeleteValue: Bool
    private var dashboardEnabledValue: Bool
    private var targetAcresPerHeadDefaultValue: Double
    private var usableAcreagePercentDefaultValue: Int
    private var recentPastureIDsValue: [UUID]
    private var homeDismissedSetupSuggestionIDsValue: Set<String>
    private var homeSetupSuggestionsExpandedValue: Bool
    private var legacyRecentPastureNamesValue: [String]

    convenience init() {
        self.init(store: UserDefaultsApplicationSettingsStore())
    }

    init(store: any ApplicationSettingsStore) {
        self.store = store
        ApplicationSettingsKeyMigrator.migrate(store: store)

        self.syncModeValue = Self.decodeSyncMode(store.object(forKey: ApplicationSettingKey.syncMode.rawValue))
        self.allowHardDeleteValue = Self.decodeBool(
            store.object(forKey: ApplicationSettingKey.allowHardDelete.rawValue),
            defaultValue: false
        )
        self.dashboardEnabledValue = Self.decodeBool(
            store.object(forKey: ApplicationSettingKey.dashboardEnabled.rawValue),
            defaultValue: false
        )
        self.targetAcresPerHeadDefaultValue = Self.validatedTargetAcresPerHead(
            Self.decodeDouble(
                store.object(forKey: ApplicationSettingKey.targetAcresPerHeadDefault.rawValue),
                defaultValue: Self.defaultTargetAcresPerHead
            )
        )
        self.usableAcreagePercentDefaultValue = Self.validatedUsableAcreagePercent(
            Self.decodeInt(
                store.object(forKey: ApplicationSettingKey.usableAcreagePercentDefault.rawValue),
                defaultValue: Self.defaultUsableAcreagePercent
            )
        )
        self.recentPastureIDsValue = Self.validatedRecentPastureIDs(
            Self.decodeUUIDs(store.object(forKey: ApplicationSettingKey.recentPastureIDs.rawValue))
        )
        self.homeDismissedSetupSuggestionIDsValue = Self.validatedStringSet(
            Self.decodeStrings(
                store.object(forKey: ApplicationSettingKey.homeDismissedSetupSuggestionIDs.rawValue),
                legacySeparator: ","
            )
        )
        self.homeSetupSuggestionsExpandedValue = Self.decodeBool(
            store.object(forKey: ApplicationSettingKey.homeSetupSuggestionsExpanded.rawValue),
            defaultValue: true
        )
        self.legacyRecentPastureNamesValue = Self.decodeStrings(
            store.object(forKey: ApplicationSettingKey.legacyRecentPastureNames.rawValue),
            legacySeparator: "|"
        )

        persistNormalizedValues()
    }

    var syncMode: SyncMode {
        get { syncModeValue }
        set { update(&syncModeValue, to: newValue, key: .syncMode, encodedValue: newValue.rawValue) }
    }

    var allowHardDelete: Bool {
        get { allowHardDeleteValue }
        set { update(&allowHardDeleteValue, to: newValue, key: .allowHardDelete, encodedValue: newValue) }
    }

    var isDashboardEnabled: Bool {
        get { dashboardEnabledValue }
        set { update(&dashboardEnabledValue, to: newValue, key: .dashboardEnabled, encodedValue: newValue) }
    }

    var targetAcresPerHeadDefault: Double {
        get { targetAcresPerHeadDefaultValue }
        set {
            let validatedValue = Self.validatedTargetAcresPerHead(newValue)
            update(
                &targetAcresPerHeadDefaultValue,
                to: validatedValue,
                key: .targetAcresPerHeadDefault,
                encodedValue: validatedValue
            )
        }
    }

    var usableAcreagePercentDefault: Int {
        get { usableAcreagePercentDefaultValue }
        set {
            let validatedValue = Self.validatedUsableAcreagePercent(newValue)
            update(
                &usableAcreagePercentDefaultValue,
                to: validatedValue,
                key: .usableAcreagePercentDefault,
                encodedValue: validatedValue
            )
        }
    }

    var recentPastureIDs: [UUID] {
        get { recentPastureIDsValue }
        set {
            let validatedValue = Self.validatedRecentPastureIDs(newValue)
            update(
                &recentPastureIDsValue,
                to: validatedValue,
                key: .recentPastureIDs,
                encodedValue: validatedValue.map(\.uuidString)
            )
        }
    }

    var homeDismissedSetupSuggestionIDs: Set<String> {
        get { homeDismissedSetupSuggestionIDsValue }
        set {
            let validatedValue = Self.validatedStringSet(newValue)
            update(
                &homeDismissedSetupSuggestionIDsValue,
                to: validatedValue,
                key: .homeDismissedSetupSuggestionIDs,
                encodedValue: validatedValue.sorted()
            )
        }
    }

    var isHomeSetupSuggestionsExpanded: Bool {
        get { homeSetupSuggestionsExpandedValue }
        set {
            update(
                &homeSetupSuggestionsExpandedValue,
                to: newValue,
                key: .homeSetupSuggestionsExpanded,
                encodedValue: newValue
            )
        }
    }

    var legacyRecentPastureNames: [String] {
        legacyRecentPastureNamesValue
    }

    func clearLegacyRecentPastureNames() {
        guard !legacyRecentPastureNamesValue.isEmpty else { return }
        legacyRecentPastureNamesValue = []
        store.removeObject(forKey: ApplicationSettingKey.legacyRecentPastureNames.rawValue)
    }

    func setPersistedChangeHandler(
        _ handler: (@MainActor (ApplicationSettingKey) -> Void)?
    ) {
        persistedChangeHandler = handler
    }

    func encodedValue(for key: ApplicationSettingKey) -> Any? {
        switch key {
        case .syncMode:
            syncMode.rawValue
        case .allowHardDelete:
            allowHardDelete
        case .dashboardEnabled:
            isDashboardEnabled
        case .targetAcresPerHeadDefault:
            targetAcresPerHeadDefault
        case .usableAcreagePercentDefault:
            usableAcreagePercentDefault
        case .recentPastureIDs:
            recentPastureIDs.map(\.uuidString)
        case .homeDismissedSetupSuggestionIDs:
            homeDismissedSetupSuggestionIDs.sorted()
        case .homeSetupSuggestionsExpanded:
            isHomeSetupSuggestionsExpanded
        case .legacyRecentPastureNames:
            legacyRecentPastureNames
        }
    }

    func applyExternalValue(_ value: Any, for key: ApplicationSettingKey) {
        switch key {
        case .syncMode:
            syncMode = Self.decodeSyncMode(value)
        case .allowHardDelete:
            allowHardDelete = Self.decodeBool(value, defaultValue: false)
        case .dashboardEnabled:
            isDashboardEnabled = Self.decodeBool(value, defaultValue: false)
        case .targetAcresPerHeadDefault:
            targetAcresPerHeadDefault = Self.decodeDouble(
                value,
                defaultValue: Self.defaultTargetAcresPerHead
            )
        case .usableAcreagePercentDefault:
            usableAcreagePercentDefault = Self.decodeInt(
                value,
                defaultValue: Self.defaultUsableAcreagePercent
            )
        case .recentPastureIDs:
            recentPastureIDs = Self.decodeUUIDs(value)
        case .homeDismissedSetupSuggestionIDs:
            homeDismissedSetupSuggestionIDs = Self.decodeStrings(value, legacySeparator: ",")
        case .homeSetupSuggestionsExpanded:
            isHomeSetupSuggestionsExpanded = Self.decodeBool(value, defaultValue: true)
        case .legacyRecentPastureNames:
            legacyRecentPastureNamesValue = Self.decodeStrings(value, legacySeparator: "|")
            store.set(legacyRecentPastureNamesValue, forKey: key.rawValue)
            persistedChangeHandler?(key)
        }
    }

    func resetToDefaults() {
        syncMode = .localOnly
        allowHardDelete = false
        isDashboardEnabled = false
        targetAcresPerHeadDefault = Self.defaultTargetAcresPerHead
        usableAcreagePercentDefault = Self.defaultUsableAcreagePercent
        recentPastureIDs = []
        homeDismissedSetupSuggestionIDs = []
        isHomeSetupSuggestionsExpanded = true
        clearLegacyRecentPastureNames()
    }

    private func persistNormalizedValues() {
        for key in ApplicationSettingKey.allCases {
            guard let value = encodedValue(for: key) else { continue }
            if key == .legacyRecentPastureNames, legacyRecentPastureNamesValue.isEmpty {
                store.removeObject(forKey: key.rawValue)
            } else {
                store.set(value, forKey: key.rawValue)
            }
        }
    }

    private func update<Value: Equatable>(
        _ storage: inout Value,
        to value: Value,
        key: ApplicationSettingKey,
        encodedValue: Any
    ) {
        guard storage != value else { return }
        storage = value
        store.set(encodedValue, forKey: key.rawValue)
        persistedChangeHandler?(key)
    }

    private static func decodeSyncMode(_ value: Any?) -> SyncMode {
        if let value = value as? SyncMode {
            return value
        }
        if let rawValue = value as? String, let mode = SyncMode(rawValue: rawValue) {
            return mode
        }
        return .localOnly
    }

    private static func decodeBool(_ value: Any?, defaultValue: Bool) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: break
            }
        }
        return defaultValue
    }

    private static func decodeDouble(_ value: Any?, defaultValue: Double) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String, let number = Double(value) { return number }
        return defaultValue
    }

    private static func decodeInt(_ value: Any?, defaultValue: Int) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String, let number = Int(value) { return number }
        return defaultValue
    }

    private static func decodeUUIDs(_ value: Any?) -> [UUID] {
        let strings: [String]
        if let values = value as? [String] {
            strings = values
        } else if let value = value as? String {
            strings = value.split(separator: "|").map(String.init)
        } else {
            strings = []
        }
        return strings.compactMap(UUID.init(uuidString:))
    }

    private static func decodeStrings(_ value: Any?, legacySeparator: Character) -> Set<String> {
        if let values = value as? [String] {
            return Set(values)
        }
        if let value = value as? String {
            return Set(value.split(separator: legacySeparator).map(String.init))
        }
        return []
    }

    private static func decodeStrings(_ value: Any?, legacySeparator: Character) -> [String] {
        let values: [String]
        if let storedValues = value as? [String] {
            values = storedValues
        } else if let storedValue = value as? String {
            values = storedValue.split(separator: legacySeparator).map(String.init)
        } else {
            values = []
        }

        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private static func validatedTargetAcresPerHead(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTargetAcresPerHead }
        return min(max(value, targetAcresPerHeadRange.lowerBound), targetAcresPerHeadRange.upperBound)
    }

    private static func validatedUsableAcreagePercent(_ value: Int) -> Int {
        min(max(value, usableAcreagePercentRange.lowerBound), usableAcreagePercentRange.upperBound)
    }

    private static func validatedRecentPastureIDs(_ values: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return values.filter { seen.insert($0).inserted }.prefix(maximumRecentPastures).map { $0 }
    }

    private static func validatedStringSet(_ values: Set<String>) -> Set<String> {
        Set(
            values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(64)
        )
    }
}
