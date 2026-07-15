//
//  RecoveryModeBannerOverlay.swift
//  yaHerd
//

import SwiftUI
import UIKit

@MainActor
final class RecoveryModeBannerOverlay {
  static let shared = RecoveryModeBannerOverlay()

  private var window: RecoveryModeOverlayWindow?

  func show(controller: RecoveryModeController) {
    if let window {
      window.controller = controller
      window.rootViewController = makeRootViewController(controller: controller)
      window.isHidden = false
      return
    }

    guard
      let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive })
        ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
    else {
      return
    }

    let overlayWindow = RecoveryModeOverlayWindow(windowScene: windowScene)
    overlayWindow.controller = controller
    overlayWindow.windowLevel = UIWindow.Level.alert + 1
    overlayWindow.backgroundColor = .clear
    overlayWindow.rootViewController = makeRootViewController(controller: controller)
    overlayWindow.isHidden = false
    window = overlayWindow
  }

  func hide() {
    window?.isHidden = true
    window = nil
  }

  private func makeRootViewController(
    controller: RecoveryModeController
  ) -> UIViewController {
    let hostingController = UIHostingController(
      rootView: RecoveryModeOverlayRoot(controller: controller)
    )
    hostingController.view.backgroundColor = .clear
    return hostingController
  }
}

private final class RecoveryModeOverlayWindow: UIWindow {
  weak var controller: RecoveryModeController?

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    if controller?.isPresentingCenter == true {
      return super.hitTest(point, with: event)
    }

    let interactiveBannerHeight = safeAreaInsets.top + RecoveryModePersistentBanner.reservedHeight
    guard point.y <= interactiveBannerHeight else { return nil }
    return super.hitTest(point, with: event)
  }
}

private struct RecoveryModeOverlayRoot: View {
  @ObservedObject var controller: RecoveryModeController

  var body: some View {
    ZStack(alignment: .top) {
      Color.clear
        .ignoresSafeArea()

      if controller.isPresentingCenter {
        Color.black.opacity(0.35)
          .ignoresSafeArea()
          .transition(.opacity)

        NavigationStack {
          RecoveryModeView(controller: controller)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                ToolbarDoneButton {
                  controller.isPresentingCenter = false
                }
              }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
          Color.clear
            .frame(height: RecoveryModePersistentBanner.reservedHeight)
            .accessibilityHidden(true)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }

      RecoveryModePersistentBanner {
        controller.isPresentingCenter = true
      }
      .zIndex(1)
    }
    .animation(.snappy, value: controller.isPresentingCenter)
  }
}

struct RecoveryModePersistentBanner: View {
  static let reservedHeight: CGFloat = 58

  let showDetails: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "externaldrive.badge.exclamationmark")
        .font(.headline)

      VStack(alignment: .leading, spacing: 1) {
        Text("RECOVERY MODE — READ ONLY")
          .font(.caption.weight(.bold))
        Text("Changes cannot be saved. Sharing and sync are disabled.")
          .font(.caption2)
      }

      Spacer(minLength: 8)

      Button("Details", action: showDetails)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(minHeight: Self.reservedHeight)
    .foregroundStyle(.white)
    .background(.red)
    .accessibilityElement(children: .contain)
  }
}
