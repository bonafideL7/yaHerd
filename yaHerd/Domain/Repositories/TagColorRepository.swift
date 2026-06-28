//
//  TagColorRepository.swift
//  yaHerd
//

import Foundation

@MainActor
protocol TagColorRepository: AnyObject {
    func fetchColors() throws -> [TagColorSnapshot]
    func upsert(_ color: TagColorSnapshot) throws
    func setDefaultColor(id: UUID) throws
    func deleteColors(ids: [UUID]) throws
    func reorder(colorIDs: [UUID]) throws
    func restoreDefaultColors() throws
}
