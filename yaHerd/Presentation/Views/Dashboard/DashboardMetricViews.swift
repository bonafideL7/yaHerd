import LucideIcons
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DashboardMetric: Identifiable {
    let id: String
    let title: String
    let value: Int
    var iconSystem: String? = nil
    var iconLucide: String? = nil
    var destination: DashboardNavigationTarget?

    init(
        title: String,
        value: Int,
        iconSystem: String? = nil,
        iconLucide: String? = nil,
        destination: DashboardNavigationTarget? = nil
    ) {
        self.id = title
        self.title = title
        self.value = value
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
        .padding(.horizontal, 16)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let lucide = item.iconLucide, let base = UIImage(lucideId: lucide) {
                    Image(uiImage: base.scaled(to: CGSize(width: 22, height: 22)))
                        .renderingMode(.template)
                } else if let system = item.iconSystem {
                    Image(systemName: system)
                }
                Spacer()
            }

            Text(item.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(item.value)")
                .font(.title2.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}
