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

enum HerdDirectoryLocation: Sendable, Equatable {
    case owned
    case shared
}

struct HerdDirectoryEntry: Identifiable, Sendable, Equatable {
    let herd: HerdSummary
    let location: HerdDirectoryLocation

    var id: UUID { herd.id }
}

/// An incomplete imported root is not selectable and must not be replaced
/// with a default Herd. Complete roots remain visible during partial imports.
struct HerdDirectorySnapshot: Sendable, Equatable {
    let availableHerds: [HerdDirectoryEntry]
    let incompleteRootCount: Int
}
