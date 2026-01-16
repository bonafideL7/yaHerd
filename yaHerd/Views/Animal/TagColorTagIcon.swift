//
//  TagColorTagIcon.swift
//  yaHerd
//

import SwiftUI

/// Colored tag glyph used throughout the app.
struct TagColorTagIcon: View {
    let color: Color
    let accessibilityLabel: String
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Image(systemName: "tag.fill")
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)

            Image(systemName: "tag")
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary.opacity(color.relativeLuminance > 0.85 ? 0.65 : 0.25))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityLabel)
    }
}
