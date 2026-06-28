import Charts
import SwiftUI

struct DashboardView: View {
    @Environment(\.dashboardRecordReader) private var dashboardRecordReader
    @Environment(\.fieldCheckOverviewReader) private var fieldCheckOverviewReader

    @State private var viewModel = DashboardViewModel()
    @State private var fieldChecksModel = FieldChecksViewModel()
    @State private var selectedPastureName: String?


    private let configuration = DashboardConfiguration()

    private var snapshot: DashboardSnapshot? {
        viewModel.snapshot
    }

    private var analytics: DashboardAnalytics? {
        snapshot?.analytics
    }

    private var pastures: [DashboardPastureItem] {
        snapshot?.pastures ?? []
    }

    private var animals: [DashboardAnimalItem] {
        snapshot?.searchableAnimals ?? []
    }

    var body: some View {
        ScrollView {
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
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 96)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .refreshable {
            loadDashboardData()
        }
        .task {
            loadDashboardData()
        }
        .onAppear {
            loadDashboardData()
        }
        .alert("Dashboard Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
                fieldChecksModel.errorMessage = nil
            }
        } message: {
            Text(dashboardErrorMessage ?? "Unknown error")
        }
    }

    private var animalTypeMixChart: some View {
        DashboardChartCard(
            title: "Animal Type Mix",
            subtitle: "Current active herd composition by animal type."
        ) {
            if animalTypeMixValues.isEmpty {
                DashboardEmptyChart(message: "No active animals are available for the animal type chart.")
            } else {
                Chart(animalTypeMixValues) { item in
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
                .frame(height: chartHeight(for: animalTypeMixValues.count))
            }
        }
    }

    private var sexMixChart: some View {
        DashboardChartCard(
            title: "Sex Mix",
            subtitle: "Active herd count by recorded sex."
        ) {
            if sexMixValues.isEmpty {
                DashboardEmptyChart(message: "No active animals are available for the sex mix chart.")
            } else {
                Chart(sexMixValues) { item in
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
            if herdLocationValues.allSatisfy({ $0.count == 0 }) {
                DashboardEmptyChart(message: "No active animals are available for the location status chart.")
            } else {
                Chart(herdLocationValues) { item in
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
                .frame(height: chartHeight(for: herdLocationValues.count))
            }
        }
    }

    private var lifecycleMetricsSection: some View {
        DashboardChartCard(
            title: "Herd Lifecycle",
            subtitle: "Year-to-date production, loss, sale, and health-record activity."
        ) {
            if snapshot == nil {
                DashboardLoadingRow(title: "Loading herd analytics…")
            } else {
                LazyVGrid(columns: summaryColumns, spacing: 12) {
                    ForEach(lifecycleMetrics) { metric in
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
            if pastureUtilizationValues.isEmpty {
                DashboardEmptyChart(message: "Add pasture acreage and target acres/head to chart stocking pressure.")
            } else {
                Chart {
                    ForEach(pastureUtilizationValues) { item in
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
                .chartXScale(domain: 0...pastureUtilizationChartUpperBound)
                .chartYSelection(value: $selectedPastureName)
                .frame(height: chartHeight(for: pastureUtilizationValues.count))

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
            if seasonalCalvingCounts.allSatisfy({ $0.count == 0 }) {
                DashboardEmptyChart(message: "No birth dates are available for recent calving seasons.")
            } else {
                Chart(seasonalCalvingCounts) { item in
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
            if monthlyMedicalRecords.isEmpty || monthlyMedicalRecords.allSatisfy({ $0.count == 0 }) {
                DashboardEmptyChart(message: "No medical records are available in the last 12 months.")
            } else {
                Chart(monthlyMedicalRecords) { item in
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
            if pinkEyeCasesByYear.allSatisfy({ $0.count == 0 }) {
                DashboardEmptyChart(message: "No pink eye records found in the last six years.")
            } else {
                Chart(pinkEyeCasesByYear) { item in
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
            if offspringByDam.isEmpty {
                DashboardEmptyChart(message: "No linked dam/offspring records are available yet.")
            } else {
                Chart(offspringByDam) { item in
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
                .frame(height: chartHeight(for: offspringByDam.count))
            }
        }
    }

    private var statusOutcomesChart: some View {
        DashboardChartCard(
            title: "Sold and Deceased Trend",
            subtitle: "Annual sold and deceased outcomes based on sale and death dates."
        ) {
            if statusOutcomesByYear.allSatisfy({ $0.count == 0 }) {
                DashboardEmptyChart(message: "No sold or deceased outcomes recorded in the last six years.")
            } else {
                Chart(statusOutcomesByYear) { item in
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
            if fieldCheckHistoryValues.isEmpty {
                DashboardEmptyChart(message: "No field check history to chart.")
            } else {
                Chart(fieldCheckHistoryValues) { item in
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
            if fieldCheckOutcomeValues.allSatisfy({ $0.value == 0 }) {
                DashboardEmptyChart(message: "No flagged animals, missing animals, or open findings in recent checks.")
            } else {
                Chart(fieldCheckOutcomeValues) { item in
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

    private var lifecycleMetrics: [DashboardLifecycleMetric] {
        analytics?.lifecycleMetrics ?? []
    }

    private var seasonalCalvingCounts: [DashboardSeasonalCalvingCount] {
        analytics?.seasonalCalvingCounts ?? []
    }

    private var monthlyMedicalRecords: [DashboardMonthlyMedicalRecordCount] {
        analytics?.monthlyMedicalRecords ?? []
    }

    private var pinkEyeCasesByYear: [DashboardYearCount] {
        analytics?.pinkEyeCasesByYear ?? []
    }

    private var offspringByDam: [DashboardOffspringDamMetric] {
        analytics?.offspringByDam ?? []
    }

    private var statusOutcomesByYear: [DashboardStatusOutcomeYearCount] {
        analytics?.statusOutcomesByYear ?? []
    }

    private var animalTypeMixValues: [DashboardCategoryCountValue] {
        AnimalType.allCases
            .map { type in
                DashboardCategoryCountValue(
                    label: type.label,
                    count: animals.filter { $0.animalType == type }.count
                )
            }
            .filter { $0.count > 0 }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
    }

    private var sexMixValues: [DashboardCategoryCountValue] {
        Sex.allCases
            .map { sex in
                DashboardCategoryCountValue(
                    label: sex.label,
                    count: animals.filter { $0.sex == sex }.count
                )
            }
            .filter { $0.count > 0 }
    }

    private var herdLocationValues: [DashboardCategoryCountValue] {
        [
            DashboardCategoryCountValue(
                label: "Pasture assigned",
                count: animals.filter { $0.location == .pasture && $0.pastureID != nil }.count
            ),
            DashboardCategoryCountValue(
                label: "Working pen",
                count: animals.filter { $0.location == .workingPen }.count
            ),
            DashboardCategoryCountValue(
                label: "Pasture unassigned",
                count: animals.filter { $0.location == .pasture && $0.pastureID == nil }.count
            )
        ]
    }

    private var pastureUtilizationValues: [DashboardPastureUtilizationValue] {
        pastures
            .compactMap { pasture in
                guard pasture.acres > 0,
                      let utilization = pasture.metrics.utilizationPercent else { return nil }

                return DashboardPastureUtilizationValue(
                    id: pasture.id,
                    name: pasture.name,
                    acres: pasture.acres,
                    utilizationPercent: utilization * 100,
                    activeAnimalCount: pasture.activeAnimalCount,
                    statusLabel: pastureStatusLabel(for: pasture)
                )
            }
            .sorted { lhs, rhs in
                if lhs.utilizationPercent != rhs.utilizationPercent { return lhs.utilizationPercent > rhs.utilizationPercent }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var selectedPastureUtilizationValue: DashboardPastureUtilizationValue? {
        guard let selectedPastureName else { return nil }
        return pastureUtilizationValues.first { $0.name == selectedPastureName }
    }

    private var pastureUtilizationChartUpperBound: Double {
        let maxValue = pastureUtilizationValues.map(\.utilizationPercent).max() ?? 100
        return max(110, (maxValue * 1.15).rounded(.up))
    }

    private var fieldCheckHistoryValues: [DashboardFieldCheckValue] {
        fieldChecksModel.sessions
            .sorted { $0.startedAt < $1.startedAt }
            .suffix(12)
            .map { session in
                DashboardFieldCheckValue(
                    id: session.id,
                    sessionLabel: session.displayTitle,
                    startedAt: session.startedAt,
                    expectedHeadCount: session.expectedHeadCountSnapshot,
                    totalSeen: session.totalSeen,
                    flaggedAnimalCount: session.flaggedAnimalCount,
                    missingAnimalCount: session.missingAnimalCount,
                    openFindingsCount: session.openFindingsCount
                )
            }
    }

    private var fieldCheckOutcomeValues: [DashboardFieldCheckOutcomeValue] {
        fieldCheckHistoryValues.flatMap { item in
            [
                DashboardFieldCheckOutcomeValue(sessionID: item.id, sessionLabel: item.shortSessionLabel, metric: "Flagged", value: item.flaggedAnimalCount),
                DashboardFieldCheckOutcomeValue(sessionID: item.id, sessionLabel: item.shortSessionLabel, metric: "Missing", value: item.missingAnimalCount),
                DashboardFieldCheckOutcomeValue(sessionID: item.id, sessionLabel: item.shortSessionLabel, metric: "Findings", value: item.openFindingsCount)
            ]
        }
    }

    private var summaryColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var dashboardErrorMessage: String? {
        viewModel.errorMessage ?? fieldChecksModel.errorMessage
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { dashboardErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                    fieldChecksModel.errorMessage = nil
                }
            }
        )
    }

    private func loadDashboardData() {
        viewModel.load(configuration: configuration, using: dashboardRecordReader)
        fieldChecksModel.load(using: fieldCheckOverviewReader)
    }

    private func chartHeight(for itemCount: Int) -> CGFloat {
        CGFloat(max(itemCount, 1)) * 44 + 36
    }

    private func pastureStatusLabel(for pasture: DashboardPastureItem) -> String {
        if pasture.isRotationReady { return "Ready" }
        if pasture.isUnderutilized { return "Low" }
        return "Normal"
    }
}

private struct DashboardCategoryCountValue: Identifiable, Hashable {
    let label: String
    let count: Int

    var id: String { label }
}

private struct DashboardPastureUtilizationValue: Identifiable, Hashable {
    let id: UUID
    let name: String
    let acres: Double
    let utilizationPercent: Double
    let activeAnimalCount: Int
    let statusLabel: String
}

private struct DashboardPastureUtilizationSelection: View {
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

private struct DashboardFieldCheckValue: Identifiable, Hashable {
    let id: UUID
    let sessionLabel: String
    let startedAt: Date
    let expectedHeadCount: Int
    let totalSeen: Int
    let flaggedAnimalCount: Int
    let missingAnimalCount: Int
    let openFindingsCount: Int

    var shortSessionLabel: String {
        let dateText = startedAt.formatted(.dateTime.month(.abbreviated).day())
        return sessionLabel == "Pasture Check" ? dateText : "\(sessionLabel) \(dateText)"
    }
}

private struct DashboardFieldCheckOutcomeValue: Identifiable, Hashable {
    let sessionID: UUID
    let sessionLabel: String
    let metric: String
    let value: Int

    var id: String {
        "\(sessionID.uuidString)-\(metric)"
    }
}

private struct DashboardChartCard<Content: View>: View {
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

private struct DashboardLifecycleTile: View {
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

private struct DashboardEmptyChart: View {
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

private struct DashboardLoadingRow: View {
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
