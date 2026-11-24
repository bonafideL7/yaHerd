import SwiftUI

struct PastureGroupDetailView: View {
    @Environment(AppCurrentHerdSelection.self) private var herdSelection
    @Environment(\.pastureFeatureDependencies) private var pastureDependencies
    private var repository: any PastureGroupDetailRepository { pastureDependencies.groupDetailRepository }
    @State private var model = PastureGroupDetailViewModel()
    private let groupID: UUID
    private let originatingHerdID: UUID?
    private let originatingSelectionRevision: UInt64

    init(groupID: UUID, originatingHerdID: UUID?, originatingSelectionRevision: UInt64) {
        self.groupID = groupID
        self.originatingHerdID = originatingHerdID
        self.originatingSelectionRevision = originatingSelectionRevision
    }

    private var isSelectionCurrent: Bool {
        guard let originatingHerdID else { return false }
        return herdSelection.currentHerdID == originatingHerdID
            && herdSelection.selectionRevision == originatingSelectionRevision
    }


    var body: some View {
        Group {
            if !isSelectionCurrent {
                ContentUnavailableView(
                    "Pasture Group unavailable",
                    systemImage: "rectangle.3.group",
                    description: Text("The selected Herd changed. Reopen this group to view its records.")
                )
            } else if let detail = model.detail {
                Form {
                    Section("Group Info") {
                        LabeledContent("Graze Days", value: "\(detail.grazeDays)")
                        LabeledContent("Rest Days", value: "\(detail.restDays)")
                        LabeledContent("Pastures", value: "\(detail.pastures.count)")
                    }

                    Section("Assign Pastures") {
                        if model.assignmentRows.isEmpty {
                            Text("No pastures available.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.assignmentRows) { row in
                                Button {
                                    guard let originatingHerdID else { return }
                                    model.toggleAssignment(
                                        row, using: repository,
                                        expectedHerdID: originatingHerdID,
                                        expectedSelectionRevision: originatingSelectionRevision,
                                        selection: herdSelection
                                    )
                                } label: {
                                    PastureGroupAssignmentRowView(row: row)
                                }
                                .buttonStyle(.plain)
                                .disabledWhenDataReadOnly()
                            }
                        }
                    }
                }
            } else if model.hasLoaded {
                ContentUnavailableView(
                    "Pasture Group unavailable",
                    systemImage: "rectangle.3.group",
                    description: Text("The selected pasture group could not be loaded.")
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(model.navigationTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ToolbarEditButton {
                    model.beginEditing(
                        expectedHerdID: originatingHerdID,
                        expectedSelectionRevision: originatingSelectionRevision,
                        selection: herdSelection
                    )
                }
                .disabled(model.detail == nil || !isSelectionCurrent)
            }
        }
        .sheet(isPresented: $model.isPresentingEditGroup) {
            if isSelectionCurrent, let detail = model.detail {
                PastureGroupEditorView(group: detail) {
                    model.reloadAfterSave(
                        groupID: groupID, using: repository,
                        expectedHerdID: originatingHerdID,
                        expectedSelectionRevision: originatingSelectionRevision,
                        selection: herdSelection
                    )
                }
            }
        }
        .task(id: groupID) {
            model.load(
                groupID: groupID, using: repository,
                expectedHerdID: originatingHerdID,
                expectedSelectionRevision: originatingSelectionRevision,
                selection: herdSelection
            )
        }
        .onChange(of: pastureDependencies.mutationStream.pastureRevision) { _, _ in
            guard isSelectionCurrent else { return }
            model.load(
                groupID: groupID, using: repository,
                expectedHerdID: originatingHerdID,
                expectedSelectionRevision: originatingSelectionRevision,
                selection: herdSelection
            )
        }
        .onChange(of: herdSelection.selectionRevision) { _, _ in
            model.resetForHerdChange()
        }
        .alert("Can’t Complete Request", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.clearError()
                }
            }
        )
    }
}

private struct PastureGroupAssignmentRowView: View {
    let row: PastureGroupAssignmentRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.isAssignedToCurrentGroup ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(row.isAssignedToCurrentGroup ? Color.green : Color.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.pasture.name)
                    .foregroundStyle(.primary)
                if let assignmentDescription = row.assignmentDescription {
                    Text(assignmentDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }
}
