//
//  HerdStorageMode.swift
//  yaHerd
//

enum HerdStorageMode: Equatable {
    case localOnly
    case iCloud
}


extension HerdStorageMode {
    var displayName: String {
        switch self {
        case .localOnly:
            "Local Only"
        case .iCloud:
            "iCloud"
        }
    }
}
