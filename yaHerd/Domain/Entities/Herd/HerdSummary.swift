//
//  HerdSummary.swift
//  yaHerd
//

import Foundation

struct HerdSummary: Identifiable, Equatable, Sendable {
    let publicID: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let schemaVersion: Int

    var id: UUID { publicID }
}
