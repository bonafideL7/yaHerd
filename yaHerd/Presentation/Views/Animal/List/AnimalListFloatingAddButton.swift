//
//  AnimalListFloatingAddButton.swift
//

import SwiftUI

struct AnimalListFloatingAddButton: View {
    let bottomPadding: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FloatingAddButtonLabel()
        }
        .padding(.trailing, 24)
        .padding(.bottom, bottomPadding)
        .accessibilityLabel("Add Animal")
        .disabledWhenDataReadOnly()
    }
}
