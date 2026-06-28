import Foundation
import Observation

@MainActor
@Observable
final class PastureTilePickerViewModel {
    private(set) var pastures: [PastureSummary] = []
    private(set) var recentPastures: [PastureSummary] = []
    var errorMessage: String?

    private var recentPastureIDs: [UUID] = []

    func load(
        using repository: any PastureListReader,
        recentPastureIDsRaw: String,
        legacyRecentPastureNamesRaw: String
    ) -> String? {
        do {
            pastures = try LoadPasturesUseCase(repository: repository).execute()
            errorMessage = nil
            return configureRecentPastures(
                idsRawValue: recentPastureIDsRaw,
                legacyNamesRawValue: legacyRecentPastureNamesRaw
            )
        } catch {
            pastures = []
            recentPastures = []
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func configureRecentPastures(
        idsRawValue: String,
        legacyNamesRawValue: String
    ) -> String? {
        let parsedIDs = RecentPasturesStore.decodeIDs(from: idsRawValue)

        if parsedIDs.isEmpty, !legacyNamesRawValue.isEmpty {
            recentPastureIDs = RecentPasturesStore.migrateNames(
                legacyNamesRawValue,
                using: pastures
            )
            refreshRecentPastures()
            return RecentPasturesStore.encode(recentPastureIDs)
        }

        recentPastureIDs = parsedIDs
        refreshRecentPastures()
        return nil
    }

    func select(_ pasture: PastureSummary) -> String {
        recentPastureIDs.removeAll { $0 == pasture.id }
        recentPastureIDs.insert(pasture.id, at: 0)
        recentPastureIDs = Array(recentPastureIDs.prefix(RecentPasturesStore.maximumRecentPastures))
        refreshRecentPastures()
        return RecentPasturesStore.encode(recentPastureIDs)
    }

    private func refreshRecentPastures() {
        recentPastures = recentPastureIDs.compactMap { id in
            pastures.first { $0.id == id }
        }
    }
}

private enum RecentPasturesStore {
    static let maximumRecentPastures = 4
    private static let separator: Character = "|"

    static func decodeIDs(from rawValue: String) -> [UUID] {
        rawValue
            .split(separator: separator)
            .compactMap { UUID(uuidString: String($0)) }
    }

    static func encode(_ ids: [UUID]) -> String {
        ids.prefix(maximumRecentPastures)
            .map(\.uuidString)
            .joined(separator: String(separator))
    }

    static func migrateNames(_ rawValue: String, using pastures: [PastureSummary]) -> [UUID] {
        let names = rawValue.split(separator: separator).map(String.init)
        var ids: [UUID] = []

        for name in names {
            guard let pasture = pastures.first(where: { $0.name == name }),
                  !ids.contains(pasture.id) else {
                continue
            }
            ids.append(pasture.id)
        }

        return Array(ids.prefix(maximumRecentPastures))
    }
}
