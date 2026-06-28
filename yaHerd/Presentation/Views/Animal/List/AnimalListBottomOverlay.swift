//
//  AnimalListBottomOverlay.swift
//

import SwiftUI

struct AnimalListBottomOverlay<InlineAccessory: View, BatchAction: View, FloatingControl: View>: View {
    let inlineEntryIsActive: Bool
    let batchMode: Bool
    let shouldShowFloatingControlBar: Bool
    let inlineAccessory: () -> InlineAccessory
    let batchActionBar: () -> BatchAction
    let floatingControlBar: () -> FloatingControl

    init(
        inlineEntryIsActive: Bool,
        batchMode: Bool,
        shouldShowFloatingControlBar: Bool,
        @ViewBuilder inlineAccessory: @escaping () -> InlineAccessory,
        @ViewBuilder batchActionBar: @escaping () -> BatchAction,
        @ViewBuilder floatingControlBar: @escaping () -> FloatingControl
    ) {
        self.inlineEntryIsActive = inlineEntryIsActive
        self.batchMode = batchMode
        self.shouldShowFloatingControlBar = shouldShowFloatingControlBar
        self.inlineAccessory = inlineAccessory
        self.batchActionBar = batchActionBar
        self.floatingControlBar = floatingControlBar
    }

    var body: some View {
        if inlineEntryIsActive {
            bottomContainer {
                inlineAccessory()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        } else if batchMode {
            bottomContainer {
                batchActionBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        } else if shouldShowFloatingControlBar {
            bottomContainer {
                floatingControlBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        } else {
            Color.clear
                .frame(height: 88)
                .allowsHitTesting(false)
        }
    }

    private func bottomContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}
