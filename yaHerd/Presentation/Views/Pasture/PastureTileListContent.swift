import SwiftUI

struct PastureEmptyStateView: View {
    let onAddPasture: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No pastures", systemImage: "leaf")
        } description: {
            Text("Add a pasture to start tracking acreage and stocking.")
        } actions: {
            Button(action: onAddPasture) {
                Text("Add Pasture")
                    .readableAccentForeground()
            }
            .buttonStyle(.borderedProminent)
                .disabledWhenDataReadOnly()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PastureNoMatchesStateView: View {
    let filter: PastureListFilter
    let onClearFilter: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Matching Pastures", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No pastures match the \(filter.label.lowercased()) filter.")
        } actions: {
            Button(action: onClearFilter) {
                Text("Clear")
                    .readableAccentForeground()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct PastureAddButton: View {
    let onAddPasture: () -> Void

    var body: some View {
        Button(action: onAddPasture) {
            FloatingAddButtonLabel()
        }
        .accessibilityLabel("Add Pasture")
        .disabledWhenDataReadOnly()
    }
}

struct PastureFilterSummaryRow: View {
    let filter: PastureListFilter
    let filteredCount: Int
    let totalCount: Int
    let onClearFilter: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label(filter.label, systemImage: "line.3.horizontal.decrease.circle")
                .font(.subheadline.weight(.semibold))

            Text("\(filteredCount) of \(totalCount)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Clear", action: onClearFilter)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
