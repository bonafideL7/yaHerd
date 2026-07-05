//
//  HerdCloudSharingControllerView.swift
//  yaHerd
//

import SwiftUI
import UIKit

struct HerdCloudSharingControllerView: UIViewControllerRepresentable {
    let systemShare: HerdSystemShare

    func makeCoordinator() -> Coordinator {
        Coordinator(systemShare: systemShare)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(
            share: systemShare.share,
            container: systemShare.container
        )
        controller.delegate = context.coordinator
        controller.availablePermissions = [
            .allowPrivate,
            .allowReadOnly,
            .allowReadWrite
        ]
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UICloudSharingController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let systemShare: HerdSystemShare

        init(systemShare: HerdSystemShare) {
            self.systemShare = systemShare
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            systemShare.title
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            Task { @MainActor in
                await systemShare.persistUpdatedShare()
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in
                await systemShare.stopSharing()
            }
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            // The controller shows the system error UI. Keep the delegate for diagnostics hooks.
        }
    }
}
