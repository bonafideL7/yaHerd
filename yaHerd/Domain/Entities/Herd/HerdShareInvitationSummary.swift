//
//  HerdShareInvitationSummary.swift
//  yaHerd
//

import Foundation

struct HerdShareInvitationSummary: Equatable, Identifiable, Sendable {
    let id: UUID
    let receivedAt: Date
    let containerIdentifier: String?
    let shareRecordName: String
    let rootRecordName: String?
    let ownerDisplayName: String?

    init(
        id: UUID = UUID(),
        receivedAt: Date = Date.now,
        containerIdentifier: String?,
        shareRecordName: String,
        rootRecordName: String?,
        ownerDisplayName: String?
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.containerIdentifier = containerIdentifier
        self.shareRecordName = shareRecordName
        self.rootRecordName = rootRecordName
        self.ownerDisplayName = ownerDisplayName
    }

    var displayOwnerName: String {
        let trimmedOwnerName = ownerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedOwnerName.isEmpty ? "Unknown Owner" : trimmedOwnerName
    }

    var displayRootRecordName: String {
        rootRecordName ?? "Unknown Root Record"
    }

    var displayContainerIdentifier: String {
        containerIdentifier ?? "Unknown iCloud Container"
    }
}
