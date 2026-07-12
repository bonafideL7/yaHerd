import SwiftUI

enum FieldChecksViewMode: Hashable {
    case all
    case inProgress
    case openFindings
    case flaggedAnimals
    case missingAnimals

    var title: String {
        switch self {
        case .all:
            return "Pasture Checks"
        case .inProgress:
            return "Open Checks"
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
    @Environment(\.fieldCheckOverviewReader) private var fieldCheckOverviewReader
    @State private var model = FieldChecksViewModel()
    @State private var showingStartPastureCheck = false

    private let mode: FieldChecksViewMode
    private let onSessionLaunch: ((FieldCheckSessionLaunchConfiguration) -> Void)?

    init(mode: FieldChecksViewMode = .all, onSessionStarted: ((UUID) -> Void)? = nil) {
        self.mode = mode
        if let onSessionStarted {
            self.onSessionLaunch = { configuration in
                onSessionStarted(configuration.sessionID)
            }
        } else {
            self.onSessionLaunch = nil
        }
    }

    init(
        mode: FieldChecksViewMode = .all,
        onSessionLaunch: ((FieldCheckSessionLaunchConfiguration) -> Void)?
    ) {
        self.mode = mode
        self.onSessionLaunch = onSessionLaunch
    }

    private var currentPastureSessions: [FieldCheckSessionSummary] {
        model.sessions.filter { !$0.isPastureArchived }
    }

    private var archivedPastureSessions: [FieldCheckSessionSummary] {
        model.sessions
            .filter(\.isPastureArchived)
            .sorted(by: sortedByStateThenNewest)
    }

    private var needsAttentionSessions: [FieldCheckSessionSummary] {
        currentPastureSessions
            .filter(isAttentionSession)
            .sorted { left, right in
                let leftScore = attentionScore(for: left)
                let rightScore = attentionScore(for: right)
                if leftScore != rightScore {
                    return leftScore > rightScore
                }
                return sortedByStateThenNewest(left, right)
            }
    }

    private var openCheckSessions: [FieldCheckSessionSummary] {
        currentPastureSessions
            .filter { !$0.isCompleted && !isAttentionSession($0) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var recentCheckSessions: [FieldCheckSessionSummary] {
        Array(
            currentPastureSessions
                .filter { $0.isCompleted && !isAttentionSession($0) }
                .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
                .prefix(12)
        )
    }

    private var openFindingSessions: [FieldCheckSessionSummary] {
        model.sessions
            .filter { $0.openFindingsCount > 0 }
            .sorted(by: sortedByStateThenNewest)
    }

    private var flaggedSessions: [FieldCheckSessionSummary] {
        model.sessions
            .filter { $0.flaggedAnimalCount > 0 }
            .sorted(by: sortedByStateThenNewest)
    }

    private var missingSessions: [FieldCheckSessionSummary] {
        model.sessions
            .filter { $0.missingAnimalCount > 0 }
            .sorted(by: sortedByStateThenNewest)
    }

    private var filteredIsEmpty: Bool {
        switch mode {
        case .all:
            return needsAttentionSessions.isEmpty
            && openCheckSessions.isEmpty
            && recentCheckSessions.isEmpty
            && archivedPastureSessions.isEmpty
        case .inProgress:
            return model.activeSessions.isEmpty
        case .openFindings:
            return openFindingSessions.isEmpty
        case .flaggedAnimals:
            return flaggedSessions.isEmpty
        case .missingAnimals:
            return missingSessions.isEmpty
        }
    }

    var body: some View {
        Group {
            if filteredIsEmpty {
                emptyState
            } else {
                List {
                    switch mode {
                    case .all:
                        allSections
                    case .inProgress:
                        inProgressSection
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
        .navigationTitle(mode.title)
        .navigationDestination(isPresented: $showingStartPastureCheck) {
            FieldCheckPastureStartListView { sessionID in
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
            }
        }
        .task {
            model.load(using: fieldCheckOverviewReader)
        }
        .alert("Can't Load Checks", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
        .profileBodyRecomputation("FieldChecksView")
    }

    @ViewBuilder
    private var emptyState: some View {
        switch mode {
        case .all:
            FieldChecksEmptyState {
                showingStartPastureCheck = true
            }
        case .inProgress:
            ContentUnavailableView(
                "No Open Checks",
                systemImage: "checklist.checked",
                description: Text("Open pasture checks will appear here until they are finished.")
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
        needsAttentionSection
        openChecksSection
        recentChecksSection
        archivedPasturesSection
    }

    private var overviewSection: some View {
        Section {
            FieldChecksOverviewCard(
                needsAttentionCount: needsAttentionSessions.count,
                openCheckCount: currentPastureSessions.filter { !$0.isCompleted }.count,
                recentCheckCount: recentCheckSessions.count,
                archivedCheckCount: archivedPastureSessions.count,
                onStartPastureCheck: {
                    showingStartPastureCheck = true
                }
            )
        }
    }

    @ViewBuilder
    private var needsAttentionSection: some View {
        if !needsAttentionSessions.isEmpty {
            Section {
                ForEach(needsAttentionSessions) { session in
                    fieldCheckNavigationRow(
                        configuration: attentionLaunchConfiguration(for: session)
                    ) {
                        FieldCheckSessionSummaryRow(session: session, emphasis: emphasis(for: session))
                    }
                }
            } header: {
                Text("Needs Attention")
            } footer: {
                Text("Checks with missing animals, flagged animals, open findings, or unfinished counts.")
            }
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
                        FieldCheckSessionSummaryRow(session: session)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var inProgressSection: some View {
        if !model.activeSessions.isEmpty {
            Section {
                ForEach(model.activeSessions.sorted { $0.startedAt > $1.startedAt }) { session in
                    fieldCheckNavigationRow(
                        configuration: FieldCheckSessionLaunchConfiguration(sessionID: session.id, opensRemainingRoster: true)
                    ) {
                        FieldCheckSessionSummaryRow(session: session, emphasis: emphasis(for: session))
                    }
                }
            } header: {
                Text("Open Checks")
            } footer: {
                Text("Finish open checks before roster counts go stale.")
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
            } header: {
                Text("Open Findings")
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
            } header: {
                Text("Flagged Animals")
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
            } header: {
                Text("Missing Animals")
            } footer: {
                Text("Each row opens the check roster filtered to missing animals.")
            }
        }
    }

    @ViewBuilder
    private var archivedPasturesSection: some View {
        if !archivedPastureSessions.isEmpty {
            Section {
                ForEach(archivedPastureSessions) { session in
                    fieldCheckNavigationRow(
                        configuration: FieldCheckSessionLaunchConfiguration(sessionID: session.id)
                    ) {
                        FieldCheckSessionSummaryRow(session: session)
                    }
                }
            } header: {
                Text("Archived Pastures")
            } footer: {
                Text("Checks kept for pastures that are no longer active.")
            }
        }
    }

    @ViewBuilder
    private var recentChecksSection: some View {
        if !recentCheckSessions.isEmpty {
            Section("Recent Checks") {
                ForEach(recentCheckSessions) { session in
                    fieldCheckNavigationRow(
                        configuration: FieldCheckSessionLaunchConfiguration(sessionID: session.id)
                    ) {
                        FieldCheckSessionSummaryRow(session: session)
                    }
                }
            }
        }
    }

    private func attentionLaunchConfiguration(for session: FieldCheckSessionSummary) -> FieldCheckSessionLaunchConfiguration {
        if session.openFindingsCount > 0 {
            return FieldCheckSessionLaunchConfiguration(sessionID: session.id, opensFindings: true)
        } else if session.missingAnimalCount > 0 {
            return FieldCheckSessionLaunchConfiguration(sessionID: session.id, opensMissingRoster: true)
        } else if session.flaggedAnimalCount > 0 {
            return FieldCheckSessionLaunchConfiguration(sessionID: session.id, opensFlaggedRoster: true)
        } else {
            return FieldCheckSessionLaunchConfiguration(sessionID: session.id, opensRemainingRoster: true)
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
        } else {
            NavigationLink {
                fieldCheckSessionDestination(configuration)
            } label: {
                label()
            }
        }
    }

    @ViewBuilder
    private func fieldCheckSessionDestination(_ configuration: FieldCheckSessionLaunchConfiguration) -> some View {
        FieldCheckSessionDetailView(
            sessionID: configuration.sessionID,
            opensFindings: configuration.opensFindings,
            opensFlaggedRoster: configuration.opensFlaggedRoster,
            opensRemainingRoster: configuration.opensRemainingRoster,
            opensMissingRoster: configuration.opensMissingRoster
        )
    }

    private func openSession(_ configuration: FieldCheckSessionLaunchConfiguration) {
        if let onSessionLaunch {
            onSessionLaunch(configuration)
        }
    }

    private func isAttentionSession(_ session: FieldCheckSessionSummary) -> Bool {
        session.openFindingsCount > 0
        || session.missingAnimalCount > 0
        || session.flaggedAnimalCount > 0
        || (!session.isCompleted && session.remainingExpectedCount > 0)
    }

    private func emphasis(for session: FieldCheckSessionSummary) -> FieldCheckSessionSummaryRow.Emphasis {
        if session.missingAnimalCount > 0 { return .missing }
        if session.openFindingsCount > 0 { return .findings }
        if session.flaggedAnimalCount > 0 { return .flagged }
        if !session.isCompleted && session.remainingExpectedCount > 0 { return .remaining }
        return .standard
    }

    private func attentionScore(for session: FieldCheckSessionSummary) -> Int {
        var score = 0
        if session.missingAnimalCount > 0 { score += 400 }
        if session.openFindingsCount > 0 { score += 300 }
        if session.flaggedAnimalCount > 0 { score += 200 }
        if !session.isCompleted && session.remainingExpectedCount > 0 { score += 100 }
        return score
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

private struct FieldChecksOverviewCard: View {
    let needsAttentionCount: Int
    let openCheckCount: Int
    let recentCheckCount: Int
    let archivedCheckCount: Int
    let onStartPastureCheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pasture Checks")
                        .font(.headline)

                    Text("Use this as a triage and history hub. Start new checks from here or from a pasture.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button(action: onStartPastureCheck) {
                    Label("Start", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], alignment: .leading, spacing: 10) {
                FieldChecksOverviewMetric(title: "Attention", value: needsAttentionCount, tint: needsAttentionCount > 0 ? .orange : .secondary)
                FieldChecksOverviewMetric(title: "Open", value: openCheckCount, tint: openCheckCount > 0 ? .accentColor : .secondary)
                FieldChecksOverviewMetric(title: "Recent", value: recentCheckCount, tint: .secondary)
                if archivedCheckCount > 0 {
                    FieldChecksOverviewMetric(title: "Archived", value: archivedCheckCount, tint: .secondary)
                }
            }
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
                .foregroundStyle(.secondary)
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
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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

        if session.openFindingsCount > 0 {
            parts.append("\(session.openFindingsCount) findings")
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
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        if session.isPastureArchived {
                            FieldCheckBadge(title: "Archived", tint: Color.secondary)
                        }

                        FieldCheckBadge(
                            title: session.isCompleted ? "Done" : "Open",
                            tint: session.isCompleted ? Color.green : Color.orange
                        )
                    }
                }

                Text(dateLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}
