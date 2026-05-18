//
//  SyncMode.swift
//  yaHerd
//

import Foundation

enum SyncMode: String, CaseIterable, Identifiable {
    case localOnly
    case iCloud

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localOnly:
            "Local Only"
        case .iCloud:
            "iCloud Sync"
        }
    }

    var storageDescription: String {
        switch self {
        case .localOnly:
            "Data is saved on this device only."
        case .iCloud:
            "Data is saved on this device and mirrored with iCloud when available."
        }
    }
}
