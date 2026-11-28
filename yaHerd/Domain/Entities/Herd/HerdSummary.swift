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

/// Last locally available share information, not a live server authorization.
/// No participant identities, invitation URLs or transport objects leave persistence.
enum HerdSharingMetadata: Equatable, Sendable {
    enum Access: Equatable, Sendable {
        case owner
        case readOnly
        case readWrite
        case pending
        case removed
        case unknown
    }

    case notConfigured
    case noCachedShare
    case unavailable
    case shared(access: Access, acceptedParticipants: Int?, pendingInvitations: Int?)

    var access: Access? {
        guard case let .shared(access, _, _) = self else { return nil }
        return access
    }
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
    /// Local store-qualified identity of the actual root, not its application UUID.
    let rootIdentity: URL
    let sharingMetadata: HerdSharingMetadata

    init(
        summary: HerdSummary,
        category: Category,
        rootIdentity: URL,
        sharingMetadata: HerdSharingMetadata = .notConfigured
    ) {
        self.summary = summary
        self.category = category
        self.rootIdentity = rootIdentity
        self.sharingMetadata = sharingMetadata
    }

    var id: UUID { summary.id }
    var name: String { summary.name }
}

/// Complete selectable Herds and whether other roots are awaiting metadata.
/// An incomplete root has no safe domain identity and is never selectable.
struct HerdInventory: Sendable {
    let herds: [AccessibleHerd]
    let hasIncompleteRoots: Bool
    let hasIncompleteOwnedRoots: Bool
    let ambiguousHerdIDs: Set<UUID>
}


/// Locally resolved authorization; the server remains authoritative.
struct HerdAuthorization: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case owner, editor, viewer, revoked, unavailable
    }

    let role: Role
    let canInsert: Bool
    let canUpdate: Bool
    let canDelete: Bool

    static func denied(_ role: Role = .unavailable) -> Self {
        Self(role: role, canInsert: false, canUpdate: false, canDelete: false)
    }

    var canManageSharing: Bool { role == .owner && canUpdate }
}
