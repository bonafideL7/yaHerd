//
//  AppAnimatedBackground.swift
//  yaHerd
//
//  Created by mm on 4/28/26.
//


import SwiftUI

struct AppAnimatedBackground: View {
    let style: AppBackgroundStyle

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            baseGradient

            if !reduceMotion {
                MeshAuroraBackground(style: style)
                    .opacity(colorScheme == .dark ? 0.55 : 0.35)

                FloatingParticlesBackground(style: style)
                    .opacity(colorScheme == .dark ? 0.35 : 0.22)
            }
        }
        .ignoresSafeArea()
    }

    private var baseGradient: some View {
        LinearGradient(
            colors: baseColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var baseColors: [Color] {
        switch style {
        case .dashboard:
            [
                Color.green.opacity(colorScheme == .dark ? 0.28 : 0.18),
                Color.brown.opacity(colorScheme == .dark ? 0.22 : 0.12),
                Color.black.opacity(colorScheme == .dark ? 0.65 : 0.03)
            ]

        case .animalDetail:
            [
                Color.teal.opacity(colorScheme == .dark ? 0.24 : 0.14),
                Color.green.opacity(colorScheme == .dark ? 0.20 : 0.10),
                Color.black.opacity(colorScheme == .dark ? 0.70 : 0.02)
            ]

        case .pasture:
            [
                Color.green.opacity(colorScheme == .dark ? 0.34 : 0.20),
                Color.yellow.opacity(colorScheme == .dark ? 0.12 : 0.10),
                Color.brown.opacity(colorScheme == .dark ? 0.24 : 0.08)
            ]

        case .fieldCheck:
            [
                Color.blue.opacity(colorScheme == .dark ? 0.22 : 0.12),
                Color.green.opacity(colorScheme == .dark ? 0.20 : 0.10),
                Color.black.opacity(colorScheme == .dark ? 0.72 : 0.02)
            ]

        case .calm:
            [
                Color.gray.opacity(colorScheme == .dark ? 0.22 : 0.08),
                Color.green.opacity(colorScheme == .dark ? 0.16 : 0.08),
                Color.black.opacity(colorScheme == .dark ? 0.72 : 0.02)
            ]
        }
    }
}