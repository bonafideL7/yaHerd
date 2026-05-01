//
//  FloatingParticlesBackground.swift
//  yaHerd
//
//  Created by mm on 4/28/26.
//


import SwiftUI

struct FloatingParticlesBackground: View {
    let style: AppBackgroundStyle

    private let particles: [BackgroundParticle] = (0..<18).map {
        BackgroundParticle(index: $0)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate

                for particle in particles {
                    let position = particle.position(in: size, time: time)
                    let rect = CGRect(
                        x: position.x,
                        y: position.y,
                        width: particle.size,
                        height: particle.size
                    )

                    context.opacity = particle.opacity

                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(particleColor.opacity(particle.opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var particleColor: Color {
        switch style {
        case .dashboard, .pasture:
            return .green
        case .animalDetail:
            return .teal
        case .fieldCheck:
            return .blue
        case .calm:
            return .gray
        }
    }
}

private struct BackgroundParticle {
    let index: Int

    var size: CGFloat {
        CGFloat(4 + (index % 5) * 2)
    }

    var opacity: Double {
        0.08 + Double(index % 4) * 0.025
    }

    func position(in size: CGSize, time: TimeInterval) -> CGPoint {
        let speed = 0.025 + Double(index % 5) * 0.006
        let phase = Double(index) * 0.74

        let xRatio = 0.5 + 0.45 * sin(time * speed + phase)
        let yRatio = 0.5 + 0.45 * cos(time * speed * 1.3 + phase)

        return CGPoint(
            x: size.width * xRatio,
            y: size.height * yRatio
        )
    }
}