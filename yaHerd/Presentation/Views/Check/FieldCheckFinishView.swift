import SwiftUI

struct FieldCheckFinishView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let detail: FieldCheckSessionDetailSnapshot
    let countProjection: FieldCheckSessionCountProjection
    let notSeenChecks: [FieldCheckAnimalCheckSnapshot]
    let onFinish: @MainActor () async -> String?

    @State private var showingUnseenConfirmation = false
    @State private var showingError = false
    @State private var errorMessage: String?
    @State private var isFinishing = false

    private var canFinish: Bool {
        dataAccessMode.allowsDataMutations && !detail.isCompleted && !isFinishing
    }

    var body: some View {
        NavigationStack {
            Form {
                summarySection

                if !notSeenChecks.isEmpty {
                    notSeenSection
                }

                if detail.openFindingsCount > 0 {
                    Section("Open Findings") {
                        Text("Open findings will remain available after the check is finished.")
                            .foregroundStyle(.secondary)
                    }
                }
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
                Button("Finish Anyway") { completeCheck() }
                    .disabled(!canFinish)
                Button("Keep Checking", role: .cancel) {}
            } message: {
                Text(unfinishedConfirmationMessage)
            }
            .safeAreaInset(edge: .bottom) {
                SessionFinishActionBar(
                    title: "Finish Check",
                    isEnabled: canFinish,
                    statusText: nil,
                    onFinish: finishTapped
                )
            }
            .alert("Can't Finish Check", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unable to finish this pasture check.")
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
                    .foregroundStyle(countProjection.remainingExpectedCount == 0 ? Color.secondary : Color.orange)
                    .monospacedDigit()
            }

            LabeledContent("Count Difference") {
                Text(countProjection.countVariance > 0
                    ? "+\(countProjection.countVariance)"
                    : "\(countProjection.countVariance)")
                    .foregroundStyle(countProjection.countVariance == 0 ? Color.secondary : Color.orange)
                    .monospacedDigit()
            }

            if detail.missingAnimalCount > 0 {
                LabeledContent("Missing") {
                    Text("\(detail.missingAnimalCount)")
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                }
            }

            if detail.openFindingsCount > 0 {
                LabeledContent("Open Findings") {
                    Text("\(detail.openFindingsCount)")
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                }
            }
        }
    }

    private var notSeenSection: some View {
        Section {
            ForEach(notSeenChecks) { check in
                HStack(spacing: 12) {
                    let tag = tagColorLibrary.resolvedDefinition(tagColorID: check.displayTagColorID)
                    let damTag = tagColorLibrary.resolvedDefinition(tagColorID: check.damDisplayTagColorID)

                    AnimalTagView(
                        tagNumber: check.displayTagNumber,
                        color: tag.color,
                        colorName: tag.name,
                        size: .compact,
                        damTagNumber: check.damDisplayTagNumber,
                        damTagColor: damTag.color,
                        damTagColorName: damTag.name
                    )

                    Spacer()

                    Text("Not Seen")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Not Seen by Tag")
        } footer: {
            Text("These animals were neither marked seen individually nor accounted for by the quick count. They will remain not seen when the check is finished.")
        }
    }

    private var unfinishedConfirmationMessage: String {
        var messages: [String] = []
        if countProjection.remainingExpectedCount > 0 {
            let noun = countProjection.remainingExpectedCount == 1 ? "animal is" : "animals are"
            messages.append("\(countProjection.remainingExpectedCount) \(noun) still not seen.")
        }

        if countProjection.countVariance != 0 {
            let difference = countProjection.countVariance
            messages.append("The count difference is \(difference > 0 ? "+" : "")\(difference).")
        }

        messages.append("You can reopen the check later if needed.")
        return messages.joined(separator: " ")
    }

    private func finishTapped() {
        guard canFinish else { return }
        if countProjection.requiresFinishConfirmation {
            showingUnseenConfirmation = true
        } else {
            completeCheck()
        }
    }

    private func completeCheck() {
        guard canFinish else { return }
        isFinishing = true

        Task { @MainActor in
            let failureMessage = await onFinish()
            isFinishing = false

            if let failureMessage {
                errorMessage = failureMessage
                showingError = true
            } else {
                dismiss()
            }
        }
    }
}
