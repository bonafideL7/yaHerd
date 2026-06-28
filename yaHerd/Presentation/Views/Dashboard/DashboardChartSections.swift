import Charts
import SwiftUI

struct DashboardChartsContent: View {
    let data: DashboardPresentationData
    let isLoaded: Bool
    @Binding var selectedPastureName: String?

    private var selectedPastureUtilizationValue: DashboardPastureUtilizationValue? {
        data.selectedPastureUtilizationValue(named: selectedPastureName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            animalTypeMixChart
            sexMixChart
            herdLocationChart
            lifecycleMetricsSection
            pastureUtilizationChart
            seasonalCalvingChart
            monthlyMedicalRecordsChart
            pinkEyeTrendChart
            offspringByDamChart
            statusOutcomesChart
            fieldCheckTrendChart
            fieldCheckOutcomesChart
        }
    }

    private var animalTypeMixChart: some View {
        DashboardChartCard(
            title: "Animal Type Mix",
            subtitle: "Current active herd composition by animal type."
        ) {
            if data.animalTypeMixValues.isEmpty {
                DashboardEmptyChart(message: "No active animals are available for the animal type chart.")
            } else {
                Chart(data.animalTypeMixValues) { item in
                    BarMark(
                        x: .value("Head", item.count),
                        y: .value("Animal Type", item.label)
                    )
                    .annotation(position: .trailing) {
                        Text(item.count.formatted())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxisLabel("Head")
                .frame(height: DashboardChartLayout.height(for: data.animalTypeMixValues.count))
            }
        }
    }

    private var sexMixChart: some View {
        DashboardChartCard(
            title: "Sex Mix",
            subtitle: "Active herd count by recorded sex."
        ) {
            if data.sexMixValues.isEmpty {
                DashboardEmptyChart(message: "No active animals are available for the sex mix chart.")
            } else {
                Chart(data.sexMixValues) { item in
                    BarMark(
                        x: .value("Sex", item.label),
                        y: .value("Head", item.count)
                    )
                    .annotation(position: .top) {
                        Text(item.count.formatted())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxisLabel("Head")
                .frame(height: 220)
            }
        }
    }

    private var herdLocationChart: some View {
        DashboardChartCard(
            title: "Pasture Assignment",
            subtitle: "Active herd count by pasture assignment state."
        ) {
            if data.herdLocationValues.allSatisfy({ $0.count == 0 }) {
                DashboardEmptyChart(message: "No active animals are available for the location status chart.")
            } else {
                Chart(data.herdLocationValues) { item in
                    BarMark(
                        x: .value("Head", item.count),
                        y: .value("Status", item.label)
                    )
                    .annotation(position: .trailing) {
                        Text(item.count.formatted())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxisLabel("Head")
                .frame(height: DashboardChartLayout.height(for: data.herdLocationValues.count))
            }
        }
    }

    private var lifecycleMetricsSection: some View {
        DashboardChartCard(
            title: "Herd Lifecycle",
            subtitle: "Year-to-date production, loss, sale, and health-record activity."
        ) {
            if !isLoaded {
                DashboardLoadingRow(title: "Loading herd analytics…")
            } else {
                LazyVGrid(columns: DashboardChartLayout.summaryColumns, spacing: 12) {
                    ForEach(data.lifecycleMetrics) { metric in
                        DashboardLifecycleTile(metric: metric)
                    }
                }
            }
        }
    }

    private var pastureUtilizationChart: some View {
        DashboardChartCard(
            title: "Pasture Utilization",
            subtitle: "Stocking pressure by pasture. Tap or drag a row to inspect the pasture details."
        ) {
            if data.pastureUtilizationValues.isEmpty {
                DashboardEmptyChart(message: "Add pasture acreage and target acres/head to chart stocking pressure.")
            } else {
                Chart {
                    ForEach(data.pastureUtilizationValues) { item in
                        BarMark(
                            x: .value("Utilization", item.utilizationPercent),
                            y: .value("Pasture", item.name)
                        )
                        .foregroundStyle(by: .value("Status", item.statusLabel))
                        .opacity(selectedPastureName == nil || selectedPastureName == item.name ? 1 : 0.35)
                        .annotation(position: .trailing) {
                            if selectedPastureName == item.name {
                                Text(item.utilizationPercent.formatted(.number.precision(.fractionLength(0))) + "%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    RuleMark(x: .value("Target", 100))
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
                .chartXAxisLabel("Utilization %")
                .chartLegend(position: .bottom)
                .chartXScale(domain: 0...data.pastureUtilizationChartUpperBound)
                .chartYSelection(value: $selectedPastureName)
                .frame(height: DashboardChartLayout.height(for: data.pastureUtilizationValues.count))

                if let selectedPastureUtilizationValue {
                    DashboardPastureUtilizationSelection(value: selectedPastureUtilizationValue)
                } else {
                    Text("The dashed line marks 100% of target stocking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var seasonalCalvingChart: some View {
        DashboardChartCard(
            title: "Calving by Season",
            subtitle: "Spring and fall calf counts across the last eight calving seasons."
        ) {
            if data.seasonalCalvingCounts.allSatisfy({ $0.count == 0 }) {
                DashboardEmptyChart(message: "No birth dates are available for recent calving seasons.")
            } else {
                Chart(data.seasonalCalvingCounts) { item in
                    BarMark(
                        x: .value("Season", item.seasonLabel),
                        y: .value("Calves", item.count)
                    )
                    .foregroundStyle(by: .value("Season", item.season.label))
                    .annotation(position: .top) {
                        if item.count > 0 {
                            Text(item.count.formatted())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYAxisLabel("Calves")
                .chartLegend(position: .bottom)
                .frame(height: 280)
            }
        }
    }

    private var monthlyMedicalRecordsChart: some View {
        DashboardChartCard(
            title: "Medical Records by Month",
            subtitle: "Monthly treatment volume for the most common recent treatment categories."
        ) {
            if data.monthlyMedicalRecords.isEmpty || data.monthlyMedicalRecords.allSatisfy({ $0.count == 0 }) {
                DashboardEmptyChart(message: "No medical records are available in the last 12 months.")
            } else {
                Chart(data.monthlyMedicalRecords) { item in
                    BarMark(
                        x: .value("Month", item.monthStart, unit: .month),
                        y: .value("Records", item.count)
                    )
                    .foregroundStyle(by: .value("Treatment", item.treatmentCategory))
                }
                .chartYAxisLabel("Records")
                .chartLegend(position: .bottom)
                .frame(height: 280)
            }
        }
    }

    private var pinkEyeTrendChart: some View {
        DashboardChartCard(
            title: "Pink Eye Trend",
            subtitle: "Annual pink eye cases detected from treatment names and health-record notes."
        ) {
            if data.pinkEyeCasesByYear.allSatisfy({ $0.count == 0 }) {
                DashboardEmptyChart(message: "No pink eye records found in the last six years.")
            } else {
                Chart(data.pinkEyeCasesByYear) { item in
                    LineMark(
                        x: .value("Year", String(item.year)),
                        y: .value("Cases", item.count)
                    )
                    PointMark(
                        x: .value("Year", String(item.year)),
                        y: .value("Cases", item.count)
                    )
                }
                .chartYAxisLabel("Cases")
                .frame(height: 240)
            }
        }
    }

    private var offspringByDamChart: some View {
        DashboardChartCard(
            title: "Offspring by Dam",
            subtitle: "Top recorded dams by number of linked offspring."
        ) {
            if data.offspringByDam.isEmpty {
                DashboardEmptyChart(message: "No linked dam/offspring records are available yet.")
            } else {
                Chart(data.offspringByDam) { item in
                    BarMark(
                        x: .value("Offspring", item.offspringCount),
                        y: .value("Dam", item.damDisplayTagNumber)
                    )
                    .annotation(position: .trailing) {
                        Text(item.offspringCount.formatted())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxisLabel("Offspring")
                .frame(height: DashboardChartLayout.height(for: data.offspringByDam.count))
            }
        }
    }

    private var statusOutcomesChart: some View {
        DashboardChartCard(
            title: "Sold and Deceased Trend",
            subtitle: "Annual sold and deceased outcomes based on sale and death dates."
        ) {
            if data.statusOutcomesByYear.allSatisfy({ $0.count == 0 }) {
                DashboardEmptyChart(message: "No sold or deceased outcomes recorded in the last six years.")
            } else {
                Chart(data.statusOutcomesByYear) { item in
                    BarMark(
                        x: .value("Year", String(item.year)),
                        y: .value("Head", item.count)
                    )
                    .foregroundStyle(by: .value("Outcome", item.outcome.label))
                }
                .chartYAxisLabel("Head")
                .chartLegend(position: .bottom)
                .frame(height: 260)
            }
        }
    }

    private var fieldCheckTrendChart: some View {
        DashboardChartCard(
            title: "Field Check Head Count Trend",
            subtitle: "Expected head count versus counted head count across recent checks."
        ) {
            if data.fieldCheckHistoryValues.isEmpty {
                DashboardEmptyChart(message: "No field check history to chart.")
            } else {
                Chart(data.fieldCheckHistoryValues) { item in
                    LineMark(
                        x: .value("Started", item.startedAt, unit: .day),
                        y: .value("Head", item.expectedHeadCount)
                    )
                    .foregroundStyle(by: .value("Metric", "Expected"))

                    LineMark(
                        x: .value("Started", item.startedAt, unit: .day),
                        y: .value("Head", item.totalSeen)
                    )
                    .foregroundStyle(by: .value("Metric", "Counted"))
                }
                .chartYAxisLabel("Head")
                .chartLegend(position: .bottom)
                .frame(height: 260)
            }
        }
    }

    private var fieldCheckOutcomesChart: some View {
        DashboardChartCard(
            title: "Field Check Issues Over Time",
            subtitle: "Flagged, missing, and open finding counts from recent pasture checks."
        ) {
            if data.fieldCheckOutcomeValues.allSatisfy({ $0.value == 0 }) {
                DashboardEmptyChart(message: "No flagged animals, missing animals, or open findings in recent checks.")
            } else {
                Chart(data.fieldCheckOutcomeValues) { item in
                    BarMark(
                        x: .value("Check", item.sessionLabel),
                        y: .value("Count", item.value)
                    )
                    .foregroundStyle(by: .value("Issue", item.metric))
                }
                .chartYAxisLabel("Count")
                .chartLegend(position: .bottom)
                .frame(height: 260)
            }
        }
    }
}

enum DashboardChartLayout {
    static let summaryColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    static func height(for itemCount: Int) -> CGFloat {
        CGFloat(max(itemCount, 1)) * 44 + 36
    }
}
