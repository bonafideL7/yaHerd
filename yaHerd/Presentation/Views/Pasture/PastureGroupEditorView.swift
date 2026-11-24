import SwiftUI

struct PastureGroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pastureFeatureDependencies) private var pastureDependencies
    @Environment(AppCurrentHerdSelection.self) private var herdSelection
    private var repository: any PastureGroupEditorRepository { pastureDependencies.groupEditorRepository }

    @State private var model = PastureGroupFormViewModel()
    @State private var hasPreparedForm = false
    @State private var editingBaseline: PastureGroupDetailSnapshot?
    @State private var originatingHerdID: UUID?
    @State private var originatingSelectionRevision: UInt64?

    private let group: PastureGroupDetailSnapshot?
    private let onSave: (() -> Void)?

    init(group: PastureGroupDetailSnapshot? = nil, onSave: (() -> Void)? = nil) {
        self.group = group
        self.onSave = onSave
    }


    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                Section("Group Info") {
                    TextField("Group Name", text: $model.name)

                    Stepper(
                        "Graze Days: \(model.grazeDays)",
                        value: $model.grazeDays,
                        in: PastureGroupInputValidator.grazeDaysRange
                    )
                    Stepper(
                        "Rest Days: \(model.restDays)",
                        value: $model.restDays,
                        in: PastureGroupInputValidator.restDaysRange
                    )
                }
            }
            .navigationTitle(group == nil ? "New Pasture Group" : "Edit Pasture Group")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarSaveButton {
                        save()
                    }
                    .disabled(!model.canSave)
                }

                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                }
            }
            .task {
                prepareFormIfNeeded()
            }
            .alert("Unable to Save", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private func prepareFormIfNeeded() {
        guard !hasPreparedForm else { return }
        hasPreparedForm = true
        originatingHerdID = herdSelection.currentHerdID
        originatingSelectionRevision = herdSelection.selectionRevision
        if let group {
            editingBaseline = group
            model.populate(from: group)
        }
    }

    private func save() {
        do {
            guard let originatingHerdID, let originatingSelectionRevision else {
                throw CancellationError()
            }
            if let baseline = editingBaseline {
                guard let current = try pastureDependencies.groupDetailRepository.fetchPastureGroupDetail(id: baseline.id),
                      current.name == baseline.name,
                      current.grazeDays == baseline.grazeDays,
                      current.restDays == baseline.restDays else {
                    model.errorMessage = "This group changed or was removed. Your draft is retained; reopen the editor before saving."
                    return
                }
                try model.update(
                    id: baseline.id,
                    using: repository,
                    expectedHerdID: originatingHerdID,
                    expectedSelectionRevision: originatingSelectionRevision,
                    selection: herdSelection
                )
            } else {
                try model.create(
                    using: repository,
                    expectedHerdID: originatingHerdID,
                    expectedSelectionRevision: originatingSelectionRevision,
                    selection: herdSelection
                )
            }
            onSave?()
            dismiss()
        } catch {
            model.errorMessage = UserVisibleErrorMessage.make(error)
        }
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
