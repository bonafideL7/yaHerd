import LucideIcons
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DashboardMetric: Identifiable {
    let id: String
    let title: String
    let value: Int
    let tint: Color
    var iconSystem: String? = nil
    var iconLucide: String? = nil
    var destination: DashboardNavigationTarget?

    init(
        title: String,
        value: Int,
        tint: Color,
        iconSystem: String? = nil,
        iconLucide: String? = nil,
        destination: DashboardNavigationTarget? = nil
    ) {
        self.id = title
        self.title = title
        self.value = value
        self.tint = tint
        self.iconSystem = iconSystem
        self.iconLucide = iconLucide
        self.destination = destination
    }
}

struct DashboardMetricsGrid: View {
    let items: [DashboardMetric]
    let onNavigate: (DashboardNavigationTarget) -> Void

    private var rows: [[DashboardMetric]] {
        stride(from: 0, to: items.count, by: 2).map { start in
            let end = min(start + 2, items.count)
            return Array(items[start..<end])
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(row) { item in
                        cell(item)
                            .frame(maxWidth: .infinity)
                    }

                    if row.count == 1 {
                        Spacer(minLength: 0)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ item: DashboardMetric) -> some View {
        if let destination = item.destination {
            Button {
                onNavigate(destination)
            } label: {
                DashboardMetricCard(item: item)
            }
            .buttonStyle(.plain)
        } else {
            DashboardMetricCard(item: item)
        }
    }
}

private struct DashboardMetricCard: View {
    let item: DashboardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                icon
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(item.tint))

                Spacer(minLength: 8)

                Text(item.value.formatted())
                    .font(.title.weight(.bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }

            Text(item.title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var icon: some View {
        if let lucide = item.iconLucide, let base = UIImage(lucideId: lucide) {
            Image(uiImage: base.scaled(to: CGSize(width: 18, height: 18)))
                .renderingMode(.template)
        } else if let system = item.iconSystem {
            Image(systemName: system)
                .font(.headline)
        } else {
            Image(systemName: "circle.fill")
                .font(.headline)
        }
    }
}
