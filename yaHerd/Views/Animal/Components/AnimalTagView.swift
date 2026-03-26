//
//  AnimalTagView.swift
//  yaHerd
//
//  Created by mm on 3/20/26.
//


import SwiftUI

struct AnimalTagView: View {
    enum Size {
        case compact
        case regular
        case prominent

        var iconSize: CGFloat {
            switch self {
            case .compact: 14
            case .regular: 16
            case .prominent: 18
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .compact: 8
            case .regular: 10
            case .prominent: 12
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .compact: 4
            case .regular: 6
            case .prominent: 8
            }
        }

        var spacing: CGFloat {
            switch self {
            case .compact: 5
            case .regular: 6
            case .prominent: 8
            }
        }

        var font: Font {
            switch self {
            case .compact:
                .footnote.monospacedDigit().weight(.semibold)
            case .regular:
                .subheadline.monospacedDigit().weight(.semibold)
            case .prominent:
                .headline.monospacedDigit().weight(.bold)
            }
        }
    }

    let tagNumber: String
    let color: Color
    let colorName: String
    var size: Size = .regular

    var body: some View {
        HStack(spacing: size.spacing) {
            TagColorTagIcon(
                color: color,
                accessibilityLabel: "Tag color: \(colorName)",
                size: size.iconSize
            )

            Text(tagNumber)
                .font(size.font)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(color.opacity(0.18), in: Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Animal tag \(colorName) \(tagNumber)")
    }
}
