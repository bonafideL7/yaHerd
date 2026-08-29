//
//  HerdCloudSharingControllerView.swift
//  yaHerd
//

import SwiftUI
import UIKit

struct HerdCloudSharingControllerView: UIViewControllerRepresentable {
  let systemShare: CloudKitSystemShare

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
      .allowReadWrite,
    ]
    return controller
  }

  func updateUIViewController(
    _ uiViewController: UICloudSharingController,
    context: Context
  ) {}

  final class Coordinator: NSObject, UICloudSharingControllerDelegate {
    private let systemShare: CloudKitSystemShare

    init(systemShare: CloudKitSystemShare) {
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
      do {
        // Persist the conservative write gate synchronously in the delegate callback. The
        // asynchronous purge task must not be the first durable evidence that CloudKit has
        // already stopped the remote share.
        try systemShare.prepareToStopSharing()
      } catch {
        ReliabilityLog.syncFailure("CloudKitSystemShare.prepareToStopSharing", error: error)
        return
      }
      Task { @MainActor in
        do {
          try await systemShare.stopSharing()
        } catch {
          ReliabilityLog.syncFailure("CloudKitSystemShare.stopSharing", error: error)
        }
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
