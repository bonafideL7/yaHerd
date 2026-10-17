import Charts
import SwiftUI

struct DashboardChartsContent: View {
    @Environment(AppNavigationState.self) private var navigation

    let data: DashboardPresentationData
    let isLoaded: Bool
    @Binding var selectedPastureName: String?

    @State private var selectedAnimalTypeLabel: String?
    @State private var selectedSexLabel: String?
    @State private var selectedLocationLabel: String?
    @State private var selectedDamID: String?

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
                .chartYSelection(value: $selectedAnimalTypeLabel)
                .frame(height: DashboardChartLayout.height(for: data.animalTypeMixValues.count))

                if let selectedAnimalTypeLabel,
                   data.animalTypeMixValues.contains(where: { $0.label == selectedAnimalTypeLabel && $0.count > 0 }),
                   let animalType = AnimalType.allCases.first(where: { $0.label == selectedAnimalTypeLabel }) {
                    Button {
                        openAnimalType(animalType)
                    } label: {
                        Label("View \(selectedAnimalTypeLabel) animals", systemImage: "arrow.up.right.square")
                    }
                }

                Menu {
                    ForEach(data.animalTypeMixValues) { item in
                        if let animalType = AnimalType.allCases.first(where: { $0.label == item.label }) {
                            Button("\(item.label) (\(item.count))") {
                                openAnimalType(animalType)
                            }
                        }
                    }
                } label: {
                    Label("Browse by animal type", systemImage: "list.bullet")
                }
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
                .chartXSelection(value: $selectedSexLabel)
                .frame(height: 220)

                if let selectedSexLabel,
                   data.sexMixValues.contains(where: { $0.label == selectedSexLabel && $0.count > 0 }),
                   let sex = Sex.allCases.first(where: { $0.label == selectedSexLabel }) {
                    Button {
                        openSex(sex)
                    } label: {
                        Label("View \(selectedSexLabel) animals", systemImage: "arrow.up.right.square")
                    }
                }

                Menu {
                    ForEach(data.sexMixValues) { item in
                        if let sex = Sex.allCases.first(where: { $0.label == item.label }) {
                            Button("\(item.label) (\(item.count))") {
                                openSex(sex)
                            }
                        }
                    }
                } label: {
                    Label("Browse by sex", systemImage: "list.bullet")
                }
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
                .chartYSelection(value: $selectedLocationLabel)
                .frame(height: DashboardChartLayout.height(for: data.herdLocationValues.count))

                if let selectedLocationLabel,
                   data.herdLocationValues.contains(where: { $0.label == selectedLocationLabel && $0.count > 0 }) {
                    Button {
                        openLocation(selectedLocationLabel)
                    } label: {
                        Label(locationActionTitle(selectedLocationLabel), systemImage: "arrow.up.right.square")
                    }
                }

                Menu {
                    ForEach(data.herdLocationValues.filter { $0.count > 0 }) { item in
                        Button("\(item.label) (\(item.count))") {
                            openLocation(item.label)
                        }
                    }
                } label: {
                    Label("Browse by location", systemImage: "list.bullet")
                }
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

                    if data.pastureUtilizationValues.filter({ $0.name == selectedPastureUtilizationValue.name }).count == 1 {
                        Button {
                            navigation.openPasture(selectedPastureUtilizationValue.id)
                        } label: {
                            Label("Open \(selectedPastureUtilizationValue.name)", systemImage: "arrow.up.right.square")
                        }
                    }
                } else {
                    Text("The dashed line marks 100% of target stocking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Menu {
                    ForEach(data.pastureUtilizationValues) { pasture in
                        Button("\(pasture.name) — \(pasture.acres.formatted(.number.precision(.fractionLength(1)))) acres") {
                            navigation.openPasture(pasture.id)
                        }
                    }
                } label: {
                    Label("Open a pasture", systemImage: "list.bullet")
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
                        y: .value("Dam", item.id.uuidString)
                    )
                    .accessibilityLabel("Dam \(item.label)")
                    .accessibilityValue("\(item.offspringCount) offspring")
                    .annotation(position: .trailing) {
                        Text(item.offspringCount.formatted())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxisLabel("Offspring")
                .chartYAxis {
                    AxisMarks(values: data.offspringByDam.map { $0.id.uuidString }) { value in
                        AxisValueLabel {
                            if let damID = value.as(String.self),
                               let dam = data.offspringByDam.first(where: { $0.id.uuidString == damID }) {
                                Text(dam.label)
                            }
                        }
                    }
                }
                .chartYSelection(value: $selectedDamID)
                .frame(height: DashboardChartLayout.height(for: data.offspringByDam.count))

                if let selectedDamID,
                   let dam = data.offspringByDam.first(where: { $0.id.uuidString == selectedDamID }) {
                    Button {
                        navigation.openAnimal(dam.id)
                    } label: {
                        Label("Open dam \(dam.label)", systemImage: "arrow.up.right.square")
                    }
                }

                Menu {
                    ForEach(data.offspringByDam) { dam in
                        Button("Dam \(dam.label) (\(dam.offspringCount))") {
                            navigation.openAnimal(dam.id)
                        }
                    }
                } label: {
                    Label("Open a dam", systemImage: "list.bullet")
                }
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

                Menu {
                    Button("Sold animals — all years") {
                        openOutcome(.sold)
                    }
                    Button("Deceased animals — all years") {
                        openOutcome(.dead)
                    }
                } label: {
                    Label("Browse outcome records (all years)", systemImage: "list.bullet")
                }
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

                Menu {
                    ForEach(data.fieldCheckHistoryValues.reversed()) { check in
                        Button("\(check.sessionLabel) — \(check.startedAt.formatted(date: .abbreviated, time: .shortened))") {
                            navigation.openFieldCheckArea(.session(
                                FieldCheckSessionLaunchConfiguration(sessionID: check.id)
                            ))
                        }
                    }
                } label: {
                    Label("Open a pasture check", systemImage: "list.bullet")
                }
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

                Menu {
                    ForEach(data.fieldCheckOutcomeValues.filter { $0.value > 0 }) { issue in
                        Button(issueActionTitle(issue)) {
                            openCheckIssue(issue)
                        }
                    }
                } label: {
                    Label("Inspect a check issue", systemImage: "list.bullet")
                }
            }
        }
    }

    private func openAnimalType(_ type: AnimalType) {
        navigation.openAnimalList(AnimalListLaunchConfiguration(
            sortOrder: .animalType,
            filter: AnimalFilter(animalType: type)
        ))
    }

    private func openSex(_ sex: Sex) {
        navigation.openAnimalList(AnimalListLaunchConfiguration(
            sortOrder: .sex,
            filter: AnimalFilter(sex: sex)
        ))
    }

    private func locationActionTitle(_ location: String) -> String {
        location == "Pasture assigned" ? "Browse pastures" : "View \(location.lowercased()) animals"
    }

    private func openLocation(_ location: String) {
        switch location {
        case "Working pen":
            navigation.openAnimalList(.workingPen)
        case "Pasture unassigned":
            navigation.openAnimalList(.missingPasture)
        case "Pasture assigned":
            // The current animal list filter cannot express "has a pasture".
            // Use the pasture list rather than implying an exact animal subset.
            navigation.openPastureList(.all)
        default:
            break
        }
    }

    private func openOutcome(_ outcome: AnimalStatus) {
        navigation.openAnimalList(AnimalListLaunchConfiguration(
            sortOrder: .status,
            filter: AnimalFilter(status: outcome),
            showRemovedStatuses: true,
            showArchivedRecords: true
        ))
    }

    private func issueActionTitle(_ issue: DashboardFieldCheckOutcomeValue) -> String {
        let startedAt = data.fieldCheckHistoryValues.first { $0.id == issue.sessionID }?.startedAt
        let dateLabel = startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown date"
        return "\(issue.sessionLabel) — \(dateLabel) — \(issue.metric) (\(issue.value))"
    }

    private func openCheckIssue(_ issue: DashboardFieldCheckOutcomeValue) {
        navigation.openFieldCheckArea(.session(FieldCheckSessionLaunchConfiguration(
            sessionID: issue.sessionID,
            opensFindings: issue.metric == "Findings",
            opensFlaggedRoster: issue.metric == "Flagged",
            opensMissingRoster: issue.metric == "Missing"
        )))
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
