//
//  PastureTileCard.swift
//  yaHerd
//
//  Created by mm on 12/8/25.
//


import SwiftUI
import LucideIcons

struct PastureTileCard: View {
    let pasture: PastureSummary
    let onTap: () -> Void

    private var headCount: Int { pasture.activeAnimalCount }

    private var acreage: String {
        if let acres = pasture.acreage {
            return acres.formatted()
        }
        return "—"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    if let icon = UIImage(lucideId: "map") {
                        Image(uiImage: icon.scaled(to: CGSize(width: 32, height: 32)))
                            .renderingMode(.template)
                            .foregroundStyle(.green)
                    }

                    Spacer(minLength: 8)

                    statusBadge
                }

                Text(pasture.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(headCount) head • \(acreage) acres")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let capacity = pasture.capacityHead, capacity > 0 {
                    ProgressView(value: min(max(Double(headCount), 0), capacity), total: capacity)
                } else if pasture.isMissingStockingData {
                    Text("Missing stocking data")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if pasture.isOverstocked {
            Label("Over", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        } else if pasture.isRotationReady {
            Label("Ready", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        } else if pasture.isUnderutilized {
            Label("Low", systemImage: "arrow.down.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } else if pasture.isMissingStockingData {
            Label("Data", systemImage: "ruler")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }
}
