//
//  TagColorDot.swift
//  yaHerd
//

import SwiftUI

struct TagColorDot: View {
    let tagColor: TagColor

    var body: some View {
        Circle()
            .fill(tagColor.color)
            .frame(width: 12, height: 12)
            .overlay(
                Circle().stroke(
                    .primary.opacity(tagColor == .white ? 0.6 : 0.25),
                    lineWidth: 1
                )
            )
            .accessibilityLabel("Tag color: \(tagColor.label)")
    }
}
