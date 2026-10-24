import SwiftUI

enum FieldChecksViewMode: String, Hashable, Codable {
    case all
    case inProgress
    case completed
    case openFindings
    case flaggedAnimals
    case missingAnimals

    static let navigationFilters: [Self] = [
        .all, .inProgress, .completed, .openFindings, .flaggedAnimals, .missingAnimals
    ]

    var filterLabel: String {
        switch self {
        case .all: "All"
        case .inProgress: "Open"
        case .completed: "Completed"
        case .openFindings: "Findings"
        case .flaggedAnimals: "Flagged"
        case .missingAnimals: "Missing"
        }
    }

    var title: String {
        switch self {
        case .all:
            return "Pasture Checks"
        case .inProgress:
            return "Open Checks"
        case .completed:
            return "Completed Checks"
        case .openFindings:
            return "Open Findings"
        case .flaggedAnimals:
            return "Flagged Animals"
        case .missingAnimals:
            return "Missing Animals"
        }
    }
}

struct FieldChecksView: View {
    @Environment(\.fieldCheckFeatureDependencies) private var fieldCheckDependencies
    @Environment(\.colorScheme) private var colorScheme
    private var fieldCheckOverviewReader: any FieldCheckOverviewReading { fieldCheckDependencies.overviewReader }
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @State private var model = FieldChecksViewModel()
    @State private var showingStartPastureCheck = false
    @State private var hasPresentedInitialStart = false

    @Binding private var selectedMode: FieldChecksViewMode
    private let startsWithPastureSelection: Bool
    private let onSessionLaunch: ((FieldCheckSessionLaunchConfiguration) -> Void)?

    init(
        mode: Binding<FieldChecksViewMode>,
        startsWithPastureSelection: Bool = false,
        onSessionLaunch: ((FieldCheckSessionLaunchConfiguration) -> Void)? = nil
    ) {
        _selectedMode = mode
        self.startsWithPastureSelection = startsWithPastureSelection
        self.onSessionLaunch = onSessionLaunch
    }

    private var openCheckSessions: [FieldCheckSessionSummary] {
        model.sessions
            .filter { !$0.isPastureArchived && !$0.isCompleted }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var completedCheckSessions: [FieldCheckSessionSummary] {
        model.sessions
            .filter { !$0.isPastureArchived && $0.isCompleted }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
    }

    private var openFindingSessions: [FieldCheckSessionSummary] {
        model.sessions
            .filter { !$0.isPastureArchived && $0.openFindingsCount > 0 }
            .sorted(by: sortedByStateThenNewest)
    }

    private var flaggedSessions: [FieldCheckSessionSummary] {
        model.sessions
            .filter { !$0.isPastureArchived && $0.flaggedAnimalCount > 0 }
            .sorted(by: sortedByStateThenNewest)
    }

    private var missingSessions: [FieldCheckSessionSummary] {
        model.sessions
            .filter { !$0.isPastureArchived && $0.missingAnimalCount > 0 }
            .sorted(by: sortedByStateThenNewest)
    }

    private var filteredIsEmpty: Bool {
        switch selectedMode {
        case .all:
            return openCheckSessions.isEmpty
        case .inProgress:
            return openCheckSessions.isEmpty
        case .completed:
            return completedCheckSessions.isEmpty
        case .openFindings:
            return openFindingSessions.isEmpty
        case .flaggedAnimals:
            return flaggedSessions.isEmpty
        case .missingAnimals:
            return missingSessions.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            checkFilters
            Group {
                if filteredIsEmpty {
                    emptyState
                } else {
                    List {
                        switch selectedMode {
                        case .all:
                            allSections
                        case .inProgress:
                            openChecksSection
                        case .completed:
                            completedChecksSection
                        case .openFindings:
                            openFindingsSection
                        case .flaggedAnimals:
                            flaggedAnimalsSection
                        case .missingAnimals:
                            missingAnimalsSection
                        }
                    }
                    .refreshable {
                        model.load(using: fieldCheckOverviewReader)
                    }
                }
            }
        }
        .navigationTitle("Pasture Checks")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingStartPastureCheck) {
            PastureSessionStartListView(kind: .fieldCheck) { sessionID in
                showingStartPastureCheck = false
                openSession(FieldCheckSessionLaunchConfiguration(sessionID: sessionID))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingStartPastureCheck = true
                } label: {
                    Label("Start", systemImage: "plus")
                }
                .accessibilityLabel("Start Pasture Check")
                .disabled(!dataAccessMode.allowsDataMutations)
            }
        }
        .task {
            if startsWithPastureSelection && !hasPresentedInitialStart {
                hasPresentedInitialStart = true
                if dataAccessMode.allowsDataMutations {
                    showingStartPastureCheck = true
                }
            }
            await model.observe(
                using: fieldCheckOverviewReader,
                mutationStream: fieldCheckDependencies.mutationStream
            )
        }
        .alert("Can't Load Checks", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
        .profileBodyRecomputation("FieldChecksView")
    }

    private var checkFilters: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FieldChecksViewMode.navigationFilters, id: \.self) { option in
                        Button {
                            selectedMode = option
                        } label: {
                            Text(option.filterLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedMode == option
                                    ? AccessibleControlContrast.accentForeground(in: colorScheme)
                                    : Color.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    selectedMode == option
                                        ? Color.accentColor
                                        : Color(.secondarySystemGroupedBackground),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.title) filter")
                        .accessibilityAddTraits(selectedMode == option ? .isSelected : [])
                        .id(option)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .task(id: selectedMode) {
                // Wait for the scroll content to lay out before revealing a preselected filter.
                await Task.yield()
                withAnimation(.snappy) {
                    proxy.scrollTo(selectedMode, anchor: .center)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var emptyState: some View {
        switch selectedMode {
        case .all:
            FieldChecksEmptyState {
                if dataAccessMode.allowsDataMutations {
                    showingStartPastureCheck = true
                }
            }
        case .inProgress:
            ContentUnavailableView(
                "No Open Checks",
                systemImage: "checklist.checked",
                description: Text("Open pasture checks will appear here until they are finished.")
            )
            .background(Color(.systemGroupedBackground))
        case .completed:
            ContentUnavailableView(
                "No Completed Checks",
                systemImage: "checkmark.circle",
                description: Text("Finished pasture checks will appear here, including those with unresolved findings.")
            )
            .background(Color(.systemGroupedBackground))
        case .openFindings:
            ContentUnavailableView(
                "No Open Findings",
                systemImage: "checkmark.circle",
                description: Text("Pasture check findings are resolved.")
            )
            .background(Color(.systemGroupedBackground))
        case .flaggedAnimals:
            ContentUnavailableView(
                "No Flagged Animals",
                systemImage: "flag",
                description: Text("Animals flagged during pasture checks will appear here.")
            )
            .background(Color(.systemGroupedBackground))
        case .missingAnimals:
            ContentUnavailableView(
                "No Missing Animals",
                systemImage: "questionmark.app",
                description: Text("Animals marked missing during pasture checks will appear here.")
            )
            .background(Color(.systemGroupedBackground))
        }
    }

    @ViewBuilder
    private var allSections: some View {
        overviewSection
        openChecksSection
    }

    private var overviewSection: some View {
        Section {
            FieldChecksOverviewCard(
                needsAttentionCount: openCheckSessions.filter { $0.openFindingsCount > 0 || $0.flaggedAnimalCount > 0 || $0.missingAnimalCount > 0 }.count,
                openCheckCount: openCheckSessions.count
            )
        }
    }

    @ViewBuilder
    private var openChecksSection: some View {
        if !openCheckSessions.isEmpty {
            Section("Open Checks") {
                ForEach(openCheckSessions) { session in
                    fieldCheckNavigationRow(
                        configuration: FieldCheckSessionLaunchConfiguration(sessionID: session.id, opensRemainingRoster: true)
                    ) {
                        FieldCheckSessionSummaryRow(session: session, emphasis: emphasis(for: session))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var openFindingsSection: some View {
        if !openFindingSessions.isEmpty {
            Section {
                ForEach(openFindingSessions) { session in
                    fieldCheckNavigationRow(
                        configuration: FieldCheckSessionLaunchConfiguration(sessionID: session.id, opensFindings: true)
                    ) {
                        FieldCheckSessionSummaryRow(session: session, emphasis: .findings)
                    }
                }
            } footer: {
                Text("Each row opens the check's Findings view.")
            }
        }
    }

    @ViewBuilder
    private var flaggedAnimalsSection: some View {
        if !flaggedSessions.isEmpty {
            Section {
                ForEach(flaggedSessions) { session in
                    fieldCheckNavigationRow(
                        configuration: FieldCheckSessionLaunchConfiguration(sessionID: session.id, opensFlaggedRoster: true)
                    ) {
                        FieldCheckSessionSummaryRow(session: session, emphasis: .flagged)
                    }
                }
            } footer: {
                Text("Each row opens the check roster filtered to flagged animals.")
            }
        }
    }

    @ViewBuilder
    private var missingAnimalsSection: some View {
        if !missingSessions.isEmpty {
            Section {
                ForEach(missingSessions) { session in
                    fieldCheckNavigationRow(
                        configuration: FieldCheckSessionLaunchConfiguration(sessionID: session.id, opensMissingRoster: true)
                    ) {
                        FieldCheckSessionSummaryRow(session: session, emphasis: .missing)
                    }
                }
            } footer: {
                Text("Each row opens the check roster filtered to missing animals.")
            }
        }
    }

    @ViewBuilder
    private var completedChecksSection: some View {
        if !completedCheckSessions.isEmpty {
            Section("Completed Checks") {
                ForEach(completedCheckSessions) { session in
                    fieldCheckNavigationRow(
                        configuration: FieldCheckSessionLaunchConfiguration(sessionID: session.id)
                    ) {
                        FieldCheckSessionSummaryRow(session: session, emphasis: emphasis(for: session))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fieldCheckNavigationRow<Label: View>(
        configuration: FieldCheckSessionLaunchConfiguration,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if onSessionLaunch != nil {
            Button {
                openSession(configuration)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                fieldCheckSessionDestination(configuration)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func fieldCheckSessionDestination(_ configuration: FieldCheckSessionLaunchConfiguration) -> some View {
        FieldCheckSessionDetailView(
            sessionID: configuration.sessionID,
            opensFindings: configuration.opensFindings,
            opensFlaggedRoster: configuration.opensFlaggedRoster,
            opensRemainingRoster: configuration.opensRemainingRoster,
            opensMissingRoster: configuration.opensMissingRoster,
            focusedFindingID: configuration.focusedFindingID
        )
    }

    private func openSession(_ configuration: FieldCheckSessionLaunchConfiguration) {
        if let onSessionLaunch {
            onSessionLaunch(configuration)
        }
    }

    private func emphasis(for session: FieldCheckSessionSummary) -> FieldCheckSessionSummaryRow.Emphasis {
        if session.missingAnimalCount > 0 { return .missing }
        if session.openFindingsCount > 0 { return .findings }
        if session.flaggedAnimalCount > 0 { return .flagged }
        if !session.isCompleted && session.remainingExpectedCount > 0 { return .remaining }
        return .standard
    }

    private func sortedByStateThenNewest(
        _ left: FieldCheckSessionSummary,
        _ right: FieldCheckSessionSummary
    ) -> Bool {
        if left.isCompleted != right.isCompleted {
            return !left.isCompleted
        }
        return left.startedAt > right.startedAt
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.errorMessage = nil
                }
            }
        )
    }
}

/// A complete, non-overlapping partition of the sessions shown by the All filter.
struct FieldCheckAllSessionGroups {
    let needsAttention: [FieldCheckSessionSummary]
    let open: [FieldCheckSessionSummary]
    let completed: [FieldCheckSessionSummary]
    let archived: [FieldCheckSessionSummary]

    // Attention is a priority group, not an additional lifecycle status.
    var openCount: Int {
        open.count + needsAttention.filter { !$0.isCompleted }.count
    }

    var completedCount: Int {
        completed.count + needsAttention.filter(\.isCompleted).count
    }

    init(sessions: [FieldCheckSessionSummary]) {
        let current = sessions.filter { !$0.isPastureArchived }

        needsAttention = current
            .filter(Self.isAttentionSession)
            .sorted { left, right in
                let leftScore = Self.attentionScore(for: left)
                let rightScore = Self.attentionScore(for: right)
                if leftScore != rightScore {
                    return leftScore > rightScore
                }
                return Self.sortedByStateThenNewest(left, right)
            }

        open = current
            .filter { !$0.isCompleted && !Self.isAttentionSession($0) }
            .sorted { $0.startedAt > $1.startedAt }

        // No history cutoff: All must include every completed check, not just the latest 12.
        completed = current
            .filter { $0.isCompleted && !Self.isAttentionSession($0) }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }

        archived = sessions
            .filter(\.isPastureArchived)
            .sorted(by: Self.sortedByStateThenNewest)
    }

    private static func isAttentionSession(_ session: FieldCheckSessionSummary) -> Bool {
        session.openFindingsCount > 0
        || session.missingAnimalCount > 0
        || session.flaggedAnimalCount > 0
        || (!session.isCompleted && session.remainingExpectedCount > 0)
    }

    private static func attentionScore(for session: FieldCheckSessionSummary) -> Int {
        var score = 0
        if session.missingAnimalCount > 0 { score += 400 }
        if session.openFindingsCount > 0 { score += 300 }
        if session.flaggedAnimalCount > 0 { score += 200 }
        if !session.isCompleted && session.remainingExpectedCount > 0 { score += 100 }
        return score
    }


    private static func sortedByStateThenNewest(
        _ left: FieldCheckSessionSummary,
        _ right: FieldCheckSessionSummary
    ) -> Bool {
        if left.isCompleted != right.isCompleted {
            return !left.isCompleted
        }
        return left.startedAt > right.startedAt
    }
}

private struct FieldChecksOverviewCard: View {
    let needsAttentionCount: Int
    let openCheckCount: Int

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], alignment: .leading, spacing: 10) {
            FieldChecksOverviewMetric(title: "Attention", value: needsAttentionCount, tint: needsAttentionCount > 0 ? .orange : .primary)
            FieldChecksOverviewMetric(title: "Open", value: openCheckCount, tint: openCheckCount > 0 ? .accentColor : .primary)
        }
        .padding(.vertical, 4)
    }
}

private struct FieldChecksOverviewMetric: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)

            Text(title)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassEffect(.regular.tint(tint.opacity(0.10)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FieldChecksEmptyState: View {
    let onStartPastureCheck: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checklist")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Pasture Checks")
                    .font(.title3.weight(.semibold))

                Text("Start a pasture check to verify head counts, record findings, and capture notes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onStartPastureCheck) {
                Label("Start Pasture Check", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .readableAccentForeground()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabledWhenDataReadOnly()
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(.systemGroupedBackground))
    }
}

private struct FieldCheckSessionSummaryRow: View {
    enum Emphasis: Equatable {
        case standard
        case remaining
        case findings
        case flagged
        case missing
    }

    let session: FieldCheckSessionSummary
    var emphasis: Emphasis = .standard

    private var iconName: String {
        switch emphasis {
        case .standard:
            return session.isCompleted ? "checkmark.circle" : "checklist"
        case .remaining:
            return "circle.dashed"
        case .findings:
            return "exclamationmark.bubble"
        case .flagged:
            return "flag"
        case .missing:
            return "questionmark.app"
        }
    }

    private var iconTint: Color {
        switch emphasis {
        case .standard:
            return session.isCompleted ? .green : .accentColor
        case .remaining:
            return .orange
        case .findings:
            return .red
        case .flagged:
            return .orange
        case .missing:
            return .brown
        }
    }

    private var statusLine: String {
        var parts: [String] = ["\(session.totalSeen)/\(session.expectedHeadCountSnapshot) seen"]

        if !session.isCompleted && session.remainingExpectedCount > 0 {
            parts.append("\(session.remainingExpectedCount) to check")
        }

        if session.missingAnimalCount > 0 {
            parts.append("\(session.missingAnimalCount) missing")
        }

        if session.flaggedAnimalCount > 0 {
            parts.append("\(session.flaggedAnimalCount) flagged")
        }

        return parts.joined(separator: " • ")
    }

    private var dateLine: String {
        if let completedAt = session.completedAt {
            return "Completed \(completedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(iconTint)
                .frame(width: 34, height: 34)
                .glassEffect(.regular.tint(iconTint.opacity(0.12)), in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.displayTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        if session.isPastureArchived {
                            FieldCheckBadge(title: "Archived", tint: Color.secondary)
                        }

                        FieldCheckBadge(
                            title: session.isCompleted ? "Check Done" : "Check Open",
                            tint: session.isCompleted ? Color.green : Color.orange
                        )
                    }
                }

                Text(dateLine)
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))

                if session.openFindingsCount > 0 {
                    FieldCheckBadge(
                        title: "\(session.openFindingsCount) Open \(session.openFindingsCount == 1 ? "Finding" : "Findings")",
                        tint: Color.red
                    )
                }

                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
