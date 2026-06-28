import SwiftUI

struct PastureEmptyStateView: View {
    let onAddPasture: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ContentUnavailableView {
            Label("No pastures", systemImage: "leaf")
        } description: {
            Text("Add a pasture to start tracking acreage and stocking.")
        } actions: {
            Button("Add Pasture", action: onAddPasture)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
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
            Button("Clear", action: onClearFilter)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct PastureAddButton: View {
    let onAddPasture: () -> Void

    var body: some View {
        Button(action: onAddPasture) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.accentColor))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        }
        .accessibilityLabel("Add Pasture")
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
