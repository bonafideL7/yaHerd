//
//  HerdSharingBridgeImportResult.swift
//  yaHerd
//

import Foundation

struct HerdSharingBridgeImportResult: Equatable {
    let herdName: String
    let insertedPastureGroupCount: Int
    let updatedPastureGroupCount: Int
    let insertedPastureCount: Int
    let updatedPastureCount: Int
    let insertedAnimalCount: Int
    let updatedAnimalCount: Int

    var importedPastureGroupCount: Int {
        insertedPastureGroupCount + updatedPastureGroupCount
    }

    var importedPastureCount: Int {
        insertedPastureCount + updatedPastureCount
    }

    var importedAnimalCount: Int {
        insertedAnimalCount + updatedAnimalCount
    }
}
