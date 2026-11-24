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

    var id: UUID { publicID }
}

/// A complete local Herd root available in an owned or joined persistent store.
/// Shared access permissions are resolved separately; store location alone
/// must never be interpreted as permission to edit.
struct AccessibleHerd: Identifiable, Equatable, Sendable {
    enum Category: Equatable, Sendable {
        case owned
        case shared
    }

    let summary: HerdSummary
    let category: Category

    var id: UUID { summary.id }
    var name: String { summary.name }
}
