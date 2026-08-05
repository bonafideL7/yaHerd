//
//  RecoveryModeBannerOverlay.swift
//  yaHerd
//

import SwiftUI

private struct RecoveryModeScenePresentationModifier: ViewModifier {
  @ObservedObject var controller: RecoveryModeController

  func body(content: Content) -> some View {
    content
      .safeAreaInset(edge: .top, spacing: 0) {
        RecoveryModePersistentBanner {
          controller.isPresentingCenter = true
        }
      }
      .sheet(isPresented: $controller.isPresentingCenter) {
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(
          controller.isPreparingExport || controller.isAttemptingRepair
        )
      }
  }
}

extension View {
  @ViewBuilder
  func recoveryModeScenePresentation(
    controller: RecoveryModeController?
  ) -> some View {
    if let controller {
      modifier(RecoveryModeScenePresentationModifier(controller: controller))
    } else {
      self
    }
  }
}

struct RecoveryModePersistentBanner: View {
  let showDetails: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "externaldrive.badge.exclamationmark")
        .font(.headline)
        .accessibilityHidden(true)

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
        .accessibilityHint("Opens storage recovery details and repair options.")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(minHeight: 58)
    .foregroundStyle(.white)
    .background(.red)
    .accessibilityElement(children: .contain)
  }
}
