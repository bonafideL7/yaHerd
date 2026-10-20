import SwiftUI

/// Review the current check before committing its completion.
struct FieldCheckFinishReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let detail: FieldCheckSessionDetailSnapshot
    let countProjection: FieldCheckSessionCountProjection
    let quickAnimalTypeCounts: [AnimalType: Int]
    let notes: String
    let isFinishing: Bool
    let canFinish: Bool
    @Binding var errorMessage: String?
    let onFinish: () -> Void

    @State private var showingUnseenConfirmation = false

    private var notSeenByTag: [FieldCheckAnimalCheckSnapshot] {
        sortedChecks.filter { !$0.wasCounted && !$0.isMissing }
    }

    private var rosterIssues: [FieldCheckAnimalCheckSnapshot] {
        sortedChecks.filter { $0.isMissing || $0.needsAttention }
    }

    private var sortedChecks: [FieldCheckAnimalCheckSnapshot] {
        detail.animalChecks.sorted {
            $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber) == .orderedAscending
        }
    }

    private var openFindingsCount: Int {
        detail.openFindingsCount
    }

    private var confirmationMessage: String {
        var warnings: [String] = []
        if countProjection.remainingExpectedCount > 0 {
            let count = countProjection.remainingExpectedCount
            warnings.append("\(count) \(count == 1 ? "animal is" : "animals are") still not seen.")
        }
        if countProjection.countVariance != 0 {
            let difference = countProjection.countVariance
            warnings.append("The count difference is \(difference > 0 ? "+" : "")\(difference).")
        }
        warnings.append("You can reopen the check later if needed.")
        return warnings.joined(separator: " ")
    }

    var body: some View {
        NavigationStack {
            Form {
                summarySection
                quickCountSection

                if !rosterIssues.isEmpty {
                    rosterIssuesSection
                }

                if !notSeenByTag.isEmpty {
                    notSeenSection
                }

                findingsSection
                notesSection
            }
            .navigationTitle("Finish Check")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isFinishing)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                        .disabled(isFinishing)
                }
            }
            .confirmationDialog(
                "Finish With Unseen Animals?",
                isPresented: $showingUnseenConfirmation,
                titleVisibility: .visible
            ) {
                Button("Finish Anyway", action: onFinish)
                    .disabled(!canFinish || isFinishing)
                Button("Keep Checking", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
            .safeAreaInset(edge: .bottom) {
                finishActionBar
            }
            .alert(
                "Can't Finish Check",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var summarySection: some View {
        Section("Check Summary") {
            LabeledContent("Seen") {
                Text("\(countProjection.totalSeen) / \(detail.expectedHeadCountSnapshot)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            LabeledContent("To Check") {
                Text("\(countProjection.remainingExpectedCount)")
                    .foregroundStyle(countProjection.remainingExpectedCount > 0 ? Color.orange : Color.secondary)
                    .monospacedDigit()
            }

            LabeledContent("Difference") {
                Text(countProjection.countVariance == 0
                    ? "Matched"
                    : "\(countProjection.countVariance > 0 ? "+" : "")\(countProjection.countVariance)")
                    .foregroundStyle(countProjection.countVariance == 0 ? Color.secondary : Color.orange)
                    .monospacedDigit()
            }

            LabeledContent("Seen by Tag") {
                Text("\(detail.individuallyVerifiedCount)")
                    .monospacedDigit()
            }

            LabeledContent("Missing") {
                Text("\(detail.missingAnimalCount)")
                    .foregroundStyle(detail.missingAnimalCount > 0 ? Color.orange : Color.secondary)
                    .monospacedDigit()
            }

            LabeledContent("Flagged") {
                Text("\(detail.flaggedAnimalCount)")
                    .foregroundStyle(detail.flaggedAnimalCount > 0 ? Color.orange : Color.secondary)
                    .monospacedDigit()
            }

            LabeledContent("Open Findings") {
                Text("\(openFindingsCount)")
                    .foregroundStyle(openFindingsCount > 0 ? Color.orange : Color.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var quickCountSection: some View {
        let counts = AnimalType.allCases.filter { quickAnimalTypeCounts[$0, default: 0] > 0 }
        if !counts.isEmpty {
            Section("Quick Count by Type") {
                ForEach(counts, id: \.self) { animalType in
                    LabeledContent(animalType.label) {
                        Text("\(quickAnimalTypeCounts[animalType, default: 0])")
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var rosterIssuesSection: some View {
        Section("Missing or Flagged") {
            ForEach(rosterIssues) { check in
                HStack {
                    Text(check.displayTagNumber)
                        .fontWeight(.medium)
                    Spacer()
                    Text(check.isMissing ? "Missing" : "Flagged")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var notSeenSection: some View {
        Section {
            ForEach(notSeenByTag) { check in
                HStack {
                    Text(check.displayTagNumber)
                        .fontWeight(.medium)
                    Spacer(minLength: 8)
                    if !check.animalName.isEmpty {
                        Text(check.animalName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        } header: {
            Text("Not Seen by Tag (\(notSeenByTag.count))")
        } footer: {
            Text("Quick counts contribute to the seen total without individually marking these tags.")
        }
    }

    private var findingsSection: some View {
        Section("Findings") {
            if detail.findings.isEmpty {
                Text("No findings recorded.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.findings.sorted(by: { $0.recordedAt > $1.recordedAt })) { finding in
                    FieldCheckFindingRow(finding: finding, showsPastureName: false)
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(trimmedNotes.isEmpty ? "No notes recorded." : trimmedNotes)
                .foregroundStyle(trimmedNotes.isEmpty ? Color.secondary : Color.primary)
        }
    }

    private var finishActionBar: some View {
        Button {
            guard canFinish, !isFinishing else { return }
            if countProjection.requiresFinishConfirmation {
                showingUnseenConfirmation = true
            } else {
                onFinish()
            }
        } label: {
            Label("Finish Check", systemImage: "checkmark.circle.fill")
                .readableAccentForeground()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!canFinish || isFinishing)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }
}
