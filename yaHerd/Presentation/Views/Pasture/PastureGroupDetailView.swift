import SwiftUI

struct PastureGroupDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var model = PastureGroupDetailViewModel()

    private let groupID: UUID

    init(groupID: UUID) {
        self.groupID = groupID
    }

    private var repository: any PastureRepository {
        dependencies.pastureRepository
    }

    var body: some View {
        Group {
            if let detail = model.detail {
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
                                    model.toggleAssignment(row, using: repository)
                                } label: {
                                    PastureGroupAssignmentRowView(row: row)
                                }
                                .buttonStyle(.plain)
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
                    model.beginEditing()
                }
                .disabled(model.detail == nil)
            }
        }
        .sheet(isPresented: $model.isPresentingEditGroup) {
            if let detail = model.detail {
                PastureGroupEditorView(group: detail) {
                    model.reloadAfterSave(groupID: groupID, using: repository)
                }
            }
        }
        .task(id: groupID) {
            model.load(groupID: groupID, using: repository)
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
