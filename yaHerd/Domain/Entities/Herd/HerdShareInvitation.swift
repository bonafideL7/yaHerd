//
//  HerdShareInvitation.swift
//  yaHerd
//

import CloudKit
import Foundation

@MainActor
struct HerdShareInvitation: Identifiable {
    let id: UUID
    let metadata: CKShare.Metadata
    let receivedAt: Date

    init(
        id: UUID = UUID(),
        metadata: CKShare.Metadata,
        receivedAt: Date = Date.now
    ) {
        self.id = id
        self.metadata = metadata
        self.receivedAt = receivedAt
    }

    var summary: HerdShareInvitationSummary {
        HerdShareInvitationSummary(
            id: id,
            receivedAt: receivedAt,
            containerIdentifier: metadata.containerIdentifier,
            shareRecordName: metadata.share.recordID.recordName,
            rootRecordName: metadata.hierarchicalRootRecordID?.recordName,
            ownerDisplayName: metadata.ownerIdentity.nameComponents?.formatted()
        )
    }
}
