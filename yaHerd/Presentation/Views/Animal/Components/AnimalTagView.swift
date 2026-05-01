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

        var damFont: Font {
            switch self {
            case .compact:
                .caption2.monospacedDigit().weight(.semibold)
            case .regular:
                .caption.monospacedDigit().weight(.semibold)
            case .prominent:
                .subheadline.monospacedDigit().weight(.semibold)
            }
        }
    }

    enum DamTagVisibility {
        case whenUntagged
        case always
    }

    let tagNumber: String
    let color: Color
    let colorName: String
    var size: Size = .regular
    var damTagNumber: String? = nil
    var damTagColor: Color? = nil
    var damTagColorName: String? = nil
    var damTagVisibility: DamTagVisibility = .whenUntagged

    private var normalizedTagText: String {
        let trimmed = tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "UT" : trimmed
    }

    private var normalizedColorName: String {
        let trimmed = colorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "White" : trimmed
    }

    private var normalizedDamTagText: String? {
        switch damTagVisibility {
        case .whenUntagged:
            guard normalizedTagText == "UT" else { return nil }
        case .always:
            break
        }

        let trimmed = damTagNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedDamColorName: String {
        let trimmed = damTagColorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "White" : trimmed
    }

    private var resolvedDamColor: Color {
        damTagColor ?? .secondary
    }

    var body: some View {
        HStack(spacing: 6) {
            baseTagPill

            if let normalizedDamTagText {
                damTagPill(normalizedDamTagText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var baseTagPill: some View {
        HStack(spacing: size.spacing) {
            TagColorTagIcon(
                color: color,
                accessibilityLabel: "Tag color: \(normalizedColorName)",
                size: size.iconSize
            )

            Text(normalizedTagText)
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
        .accessibilityLabel("Animal tag \(normalizedColorName) \(normalizedTagText)")
    }

    private func damTagPill(_ tagText: String) -> some View {
        HStack(spacing: 4) {
            
            TagColorTagIcon(
                color: resolvedDamColor,
                accessibilityLabel: "Dam tag color: \(normalizedDamColorName)",
                size: max(size.iconSize - 3, 10)
            )

            Text(tagText)
                .font(size.damFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, max(size.horizontalPadding - 2, 6))
        .padding(.vertical, max(size.verticalPadding - 1, 3))
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(resolvedDamColor.opacity(0.28), lineWidth: 1)
        )
        .accessibilityLabel("Dam tag \(normalizedDamColorName) \(tagText)")
    }
}
