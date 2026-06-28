import SwiftUI

struct DashboardChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }
}

struct DashboardLifecycleTile: View {
    let metric: DashboardLifecycleMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: metric.systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.value.formatted())
                    .font(.title.weight(.bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()

                Text(metric.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }
}

struct DashboardPastureUtilizationSelection: View {
    let value: DashboardPastureUtilizationValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value.name)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 16) {
                DashboardSelectionMetric(
                    title: "Utilization",
                    value: value.utilizationPercent.formatted(.number.precision(.fractionLength(0))) + "%"
                )

                DashboardSelectionMetric(
                    title: "Acres",
                    value: value.acres.formatted(.number.precision(.fractionLength(1)))
                )

                DashboardSelectionMetric(
                    title: "Head",
                    value: value.activeAnimalCount.formatted()
                )

                DashboardSelectionMetric(
                    title: "Status",
                    value: value.statusLabel
                )
            }
        }
        .font(.caption)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }
}

struct DashboardEmptyChart: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "No Chart Data",
            systemImage: "chart.bar.xaxis",
            description: Text(message)
        )
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct DashboardLoadingRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 18)
    }
}

private struct DashboardSelectionMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.secondary)

            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
    }
}
