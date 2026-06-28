//
//  TagColorLibraryRules.swift
//  yaHerd
//

import Foundation

enum TagColorDuplicateResolutionPolicy {
    case newestNonDefaultWins
    case stableSortOrderWins
}

enum TagColorLibraryRules {
    static func normalizedDisplayName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedNameKey(_ name: String) -> String {
        normalizedDisplayName(name)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    static func normalizedPrefix(_ prefix: String, fallbackName: String) -> String {
        let cleanedPrefix = prefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        return cleanedPrefix.isEmpty ? defaultPrefix(for: fallbackName) : cleanedPrefix
    }

    static func defaultPrefix(for name: String) -> String {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        let letters = cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap(\.first)
            .map { String($0).uppercased() }

        let joined = letters.joined()
        return joined.isEmpty ? "?" : joined
    }
}

enum TagColorDefaults {
    static let yellowID = stableID("4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D01")
    static let whiteID = stableID("4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D02")
    static let redID = stableID("4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D04")
    static let orangeID = stableID("4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D05")
    static let greenID = stableID("4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D06")
    static let blueID = stableID("4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D07")
    static let purpleID = stableID("4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D08")
    static let pinkID = stableID("4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D09")

    static let defaultColorIDs: Set<UUID> = [
        yellowID,
        whiteID,
        redID,
        orangeID,
        greenID,
        blueID,
        purpleID,
        pinkID
    ]

    static let retiredDefaultColorIDs: Set<UUID> = [
        stableID("4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D03"),
        stableID("4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D0A"),
        stableID("4D4996E2-B17D-4C0B-9E4D-8DFB60BC0D0B")
    ]

    static func seedDefaultColors() -> [TagColorSnapshot] {
        [
            TagColorSnapshot(id: yellowID, name: "Yellow", rgba: RGBAColor(r: 1, g: 1, b: 0), sortOrder: 0),
            TagColorSnapshot(id: whiteID, name: "White", rgba: RGBAColor(r: 1, g: 1, b: 1), sortOrder: 1, isDefault: true),
            TagColorSnapshot(id: redID, name: "Red", rgba: RGBAColor(r: 1, g: 0, b: 0), sortOrder: 2),
            TagColorSnapshot(id: orangeID, name: "Orange", rgba: RGBAColor(r: 1, g: 0.5, b: 0), sortOrder: 3),
            TagColorSnapshot(id: greenID, name: "Green", rgba: RGBAColor(r: 0, g: 0.7, b: 0.2), sortOrder: 4),
            TagColorSnapshot(id: blueID, name: "Blue", rgba: RGBAColor(r: 0, g: 0.48, b: 1), sortOrder: 5),
            TagColorSnapshot(id: purpleID, name: "Purple", rgba: RGBAColor(r: 0.6, g: 0.4, b: 1), sortOrder: 6),
            TagColorSnapshot(id: pinkID, name: "Pink", rgba: RGBAColor(r: 1, g: 0.2, b: 0.6), sortOrder: 7)
        ]
    }

    private static func stableID(_ rawValue: String, file: StaticString = #file, line: UInt = #line) -> UUID {
        guard let id = UUID(uuidString: rawValue) else {
            preconditionFailure("Invalid stable tag color UUID: \(rawValue)", file: file, line: line)
        }

        return id
    }
}
