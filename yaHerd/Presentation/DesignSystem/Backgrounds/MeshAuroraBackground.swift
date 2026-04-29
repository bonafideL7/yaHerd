//
//  MeshAuroraBackground.swift
//  yaHerd
//
//  Created by mm on 4/28/26.
//


import SwiftUI

struct MeshAuroraBackground: View {
    let style: AppBackgroundStyle

    @State private var animate = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                blob(
                    color: colors[0],
                    size: 360,
                    x: sin(time * 0.18) * 90,
                    y: cos(time * 0.15) * 130
                )

                blob(
                    color: colors[1],
                    size: 300,
                    x: cos(time * 0.14) * 120,
                    y: sin(time * 0.20) * 110
                )

                blob(
                    color: colors[2],
                    size: 260,
                    x: sin(time * 0.12 + 1.5) * 150,
                    y: cos(time * 0.17 + 2.0) * 140
                )
            }
            .blur(radius: 55)
            .drawingGroup()
        }
    }

    private func blob(
        color: Color,
        size: CGFloat,
        x: CGFloat,
        y: CGFloat
    ) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(x: x, y: y)
    }

    private var colors: [Color] {
        switch style {
        case .dashboard:
            [
                Color.green.opacity(0.55),
                Color.mint.opacity(0.35),
                Color.brown.opacity(0.28)
            ]

        case .animalDetail:
            [
                Color.teal.opacity(0.42),
                Color.green.opacity(0.34),
                Color.cyan.opacity(0.24)
            ]

        case .pasture:
            [
                Color.green.opacity(0.55),
                Color.yellow.opacity(0.22),
                Color.brown.opacity(0.30)
            ]

        case .fieldCheck:
            [
                Color.blue.opacity(0.35),
                Color.green.opacity(0.32),
                Color.mint.opacity(0.26)
            ]

        case .calm:
            [
                Color.gray.opacity(0.28),
                Color.green.opacity(0.22),
                Color.teal.opacity(0.18)
            ]
        }
    }
}