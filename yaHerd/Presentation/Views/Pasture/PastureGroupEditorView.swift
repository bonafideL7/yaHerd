import SwiftUI

struct PastureGroupEditorView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss

    @State private var model = PastureGroupFormViewModel()
    @State private var hasPreparedForm = false

    private let group: PastureGroupDetailSnapshot?
    private let onSave: (() -> Void)?

    init(group: PastureGroupDetailSnapshot? = nil, onSave: (() -> Void)? = nil) {
        self.group = group
        self.onSave = onSave
    }

    private var repository: any PastureRepository {
        dependencies.pastureRepository
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
        if let group {
            model.populate(from: group)
        }
    }

    private func save() {
        do {
            if let group {
                try model.update(id: group.id, using: repository)
            } else {
                try model.create(using: repository)
            }
            onSave?()
            dismiss()
        } catch {
            model.errorMessage = error.localizedDescription
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
