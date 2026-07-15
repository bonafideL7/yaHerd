//
//  HerdSystemShare.swift
//  yaHerd
//

import CloudKit
import Foundation

@MainActor
final class HerdSystemShare: Identifiable {
    let id = UUID()
    let title: String
    let share: CKShare
    let container: CKContainer
    private let persistUpdatedShareHandler: @MainActor (CKShare) async -> Void
    private let stopSharingHandler: @MainActor (CKShare) async -> Void

    init(
        title: String,
        share: CKShare,
        container: CKContainer,
        persistUpdatedShareHandler: @escaping @MainActor (CKShare) async -> Void,
        stopSharingHandler: @escaping @MainActor (CKShare) async -> Void
    ) {
        self.title = title
        self.share = share
        self.container = container
        self.persistUpdatedShareHandler = persistUpdatedShareHandler
        self.stopSharingHandler = stopSharingHandler
    }

    @MainActor
    func persistUpdatedShare() async {
        await persistUpdatedShareHandler(share)
    }

    @MainActor
    func stopSharing() async {
        await stopSharingHandler(share)
    }
}
