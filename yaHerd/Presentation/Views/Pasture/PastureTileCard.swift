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
    var isManaging = false
    var isDragging = false
    var onDelete: (() -> Void)?
    let onTap: () -> Void

    @State private var isJiggling = false

    private static let managementControlInset: CGFloat = 10

    private var headCount: Int { pasture.activeAnimalCount }

    private var acreage: String {
        if let acres = pasture.acreage {
            return acres.formatted()
        }
        return "—"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardContent
                .padding(.top, managementChromeInset)
                .padding(.leading, managementChromeInset)

            if showsDeleteControl, let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2.weight(.semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .background(Circle().fill(.background))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(pasture.name)")
                .zIndex(1)
            }
        }
        .rotationEffect(isManaging && isJiggling ? .degrees(1.2) : .zero)
        .shadow(
            color: isDragging ? .black.opacity(0.18) : .clear,
            radius: isDragging ? 18 : 0,
            y: isDragging ? 10 : 0
        )
        .animation(.snappy(duration: 0.18), value: isDragging)
        .onTapGesture {
            guard !isManaging else { return }
            onTap()
        }
        .onAppear {
            updateJiggleAnimation(isManaging)
        }
        .onChange(of: isManaging) { _, newValue in
            updateJiggleAnimation(newValue)
        }
        .accessibilityHint(isManaging ? "Drag to reorder." : "Opens pasture details.")
        .accessibilityAction(named: "Delete") {
            guard isManaging else { return }
            onDelete?()
        }
    }

    private var cardContent: some View {
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
        .background(cardBackgroundStyle, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var managementChromeInset: CGFloat {
        isManaging ? Self.managementControlInset : 0
    }

    private var showsDeleteControl: Bool {
        isManaging
    }

    private var cardBackgroundStyle: AnyShapeStyle {
        if isDragging {
            return AnyShapeStyle(Color(.secondarySystemBackground))
        }

        return AnyShapeStyle(.thinMaterial)
    }

    private func updateJiggleAnimation(_ isActive: Bool) {
        guard isActive else {
            isJiggling = false
            return
        }

        withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) {
            isJiggling = true
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if pasture.isOverCapacity {
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
