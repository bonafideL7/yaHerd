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
            return "Checks Not Completed"
        case .openFindings:
            return "Open Findings"
        case .flaggedAnimals:
            return "Flagged Check Animals"
        case .missingAnimals:
            return "Missing Check Animals"
        }
    }
}

struct FieldChecksView: View {
    @Environment(\.fieldCheckOverviewReader) private var fieldCheckOverviewReader
    @State private var model = FieldChecksViewModel()
    @State private var showingStartPastureCheck = false

    private let mode: FieldChecksViewMode

    init(mode: FieldChecksViewMode = .all) {
        self.mode = mode
    }

    private var flaggedSessions: [FieldCheckSessionSummary] {
        model.sessions
            .filter { $0.flaggedAnimalCount > 0 }
            .sorted { left, right in
                if left.isCompleted != right.isCompleted {
                    return !left.isCompleted
                }
                return left.startedAt > right.startedAt
            }
    }

    private var missingSessions: [FieldCheckSessionSummary] {
        model.sessions
            .filter { $0.missingAnimalCount > 0 }
            .sorted { left, right in
                if left.isCompleted != right.isCompleted {
                    return !left.isCompleted
                }
                return left.startedAt > right.startedAt
            }
    }

    private var filteredIsEmpty: Bool {
        switch mode {
        case .all:
            return model.activeSessions.isEmpty
            && model.openFindings.isEmpty
            && flaggedSessions.isEmpty
            && missingSessions.isEmpty
            && model.recentSessions.isEmpty
        case .inProgress:
            return model.activeSessions.isEmpty
        case .openFindings:
            return model.openFindings.isEmpty
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
            FieldCheckSessionDetailView()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingStartPastureCheck = true
                } label: {
                    Image(systemName: "plus")
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
                "No unfinished checks",
                systemImage: "checklist.checked",
                description: Text("All pasture checks have been completed.")
            )
            .background(Color(.systemGroupedBackground))
        case .openFindings:
            ContentUnavailableView(
                "No open findings",
                systemImage: "checkmark.circle",
                description: Text("Field-check findings are resolved.")
            )
            .background(Color(.systemGroupedBackground))
        case .flaggedAnimals:
            ContentUnavailableView(
                "No flagged check animals",
                systemImage: "flag",
                description: Text("No animals are marked for attention in pasture checks.")
            )
            .background(Color(.systemGroupedBackground))
        case .missingAnimals:
            ContentUnavailableView(
                "No missing check animals",
                systemImage: "questionmark.app",
                description: Text("No animals are marked missing in pasture checks.")
            )
            .background(Color(.systemGroupedBackground))
        }
    }

    @ViewBuilder
    private var allSections: some View {
        inProgressSection
        openFindingsSection
        flaggedAnimalsSection
        missingAnimalsSection
        recentChecksSection
    }

    @ViewBuilder
    private var inProgressSection: some View {
        if !model.activeSessions.isEmpty {
            Section("In Progress") {
                ForEach(model.activeSessions) { session in
                    NavigationLink {
                        FieldCheckSessionDetailView(sessionID: session.id, opensRemainingRoster: true)
                    } label: {
                        FieldCheckSessionSummaryRow(session: session)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var openFindingsSection: some View {
        if !model.openFindings.isEmpty {
            Section("Open Findings") {
                ForEach(model.openFindings) { finding in
                    NavigationLink {
                        openFindingDestination(for: finding)
                    } label: {
                        FieldCheckFindingRow(finding: finding)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var flaggedAnimalsSection: some View {
        if !flaggedSessions.isEmpty {
            Section("Flagged Animals") {
                ForEach(flaggedSessions) { session in
                    NavigationLink {
                        FieldCheckSessionDetailView(sessionID: session.id, opensFlaggedRoster: true)
                    } label: {
                        FieldCheckSessionSummaryRow(session: session, emphasis: .flagged)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var missingAnimalsSection: some View {
        if !missingSessions.isEmpty {
            Section("Missing Animals") {
                ForEach(missingSessions) { session in
                    NavigationLink {
                        FieldCheckSessionDetailView(sessionID: session.id, opensMissingRoster: true)
                    } label: {
                        FieldCheckSessionSummaryRow(session: session, emphasis: .missing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentChecksSection: some View {
        if !model.recentSessions.isEmpty {
            Section("Recent Checks") {
                ForEach(model.recentSessions) { session in
                    NavigationLink {
                        FieldCheckSessionDetailView(sessionID: session.id)
                    } label: {
                        FieldCheckSessionSummaryRow(session: session)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func openFindingDestination(for finding: FieldCheckFindingSnapshot) -> some View {
        FieldCheckSessionDetailView(sessionID: finding.sessionID, opensFindings: true)
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

private struct FieldChecksEmptyState: View {
    let onStartPastureCheck: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checklist")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No pasture checks")
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
        case flagged
        case missing
    }

    let session: FieldCheckSessionSummary
    var emphasis: Emphasis = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle)
                        .fontWeight(.semibold)
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                FieldCheckBadge(
                    title: session.isCompleted ? "Done" : "Open",
                    tint: session.isCompleted ? Color.green : Color.orange
                )
            }

            HStack(spacing: 10) {
                if let pastureName = session.pastureName {
                    Label(pastureName, systemImage: "leaf")
                }

                Label("\(session.totalSeen)/\(session.expectedHeadCountSnapshot)", systemImage: "number.circle")

                if emphasis == .flagged, session.flaggedAnimalCount > 0 {
                    Label("\(session.flaggedAnimalCount)", systemImage: "flag")
                        .foregroundStyle(.orange)
                } else if emphasis == .missing, session.missingAnimalCount > 0 {
                    Label("\(session.missingAnimalCount)", systemImage: "questionmark.app")
                        .foregroundStyle(.orange)
                } else if session.openFindingsCount > 0 {
                    Label("\(session.openFindingsCount)", systemImage: "exclamationmark.circle")
                } else if session.remainingExpectedCount > 0 && !session.isCompleted {
                    Label("\(session.remainingExpectedCount) left", systemImage: "circle.dashed")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
