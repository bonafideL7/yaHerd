//
//  AnimalListFloatingAddButton.swift
//

import SwiftUI

struct AnimalListFloatingAddButton: View {
    let bottomPadding: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.accentColor))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        }
        .padding(.trailing, 24)
        .padding(.bottom, bottomPadding)
        .accessibilityLabel("Add Animal")
    }
}
