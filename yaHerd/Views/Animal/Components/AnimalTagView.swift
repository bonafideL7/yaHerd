//
//  AnimalTagView.swift
//  yaHerd
//
//  Created by mm on 3/20/26.
//


import SwiftUI
import SwiftData

struct AnimalTagView: View {
    let tagNumber: String
    let color: Color
    let colorName: String
    
    var body: some View {
        HStack(spacing: 6) {
            TagColorTagIcon(
                color: color,
                accessibilityLabel: "Tag color: \(colorName)"
            )
            
            Text(tagNumber)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.18), in: Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
    }
}
