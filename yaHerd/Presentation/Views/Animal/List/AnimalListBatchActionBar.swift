//
//  AnimalListBatchActionBar.swift
//

import SwiftUI

struct AnimalListBatchActionBar: View {
    let selectedCount: Int
    let allVisibleAnimalsSelected: Bool
    let onToggleSelectAllVisible: () -> Void
    let onMove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedCount == 0 ? "Selection Mode" : "\(selectedCount) Selected")
                    .font(.caption)

                Button(allVisibleAnimalsSelected ? "Deselect All" : "Select All") {
                    onToggleSelectAllVisible()
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.automatic)
            }

            Spacer()

            Button(action: onMove) {
                Label("Move", systemImage: "arrowshape.turn.up.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCount == 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .shadow(radius: 10, y: 4)
    }
}

struct AnimalListFilterChip: Identifiable {
    let id = UUID()
    let title: String
    let remove: () -> Void
}
