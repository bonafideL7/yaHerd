//
//  HerdSharingBridgeImportResult.swift
//  yaHerd
//

import Foundation

struct HerdSharingBridgeImportResult: Equatable {
    let herdName: String
    let insertedAnimalCount: Int
    let updatedAnimalCount: Int

    var importedAnimalCount: Int {
        insertedAnimalCount + updatedAnimalCount
    }
}
