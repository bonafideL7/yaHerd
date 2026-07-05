//
//  SyncMode+HerdStorageMode.swift
//  yaHerd
//

extension SyncMode {
    var herdStorageMode: HerdStorageMode {
        switch self {
        case .localOnly:
            .localOnly
        case .iCloud:
            .iCloud
        }
    }
}
