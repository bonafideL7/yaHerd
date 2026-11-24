import SwiftUI

struct AddPastureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pastureFeatureDependencies) private var pastureDependencies
    @Environment(AppCurrentHerdSelection.self) private var herdSelection
    private var repository: any PastureCreateRepository { pastureDependencies.createRepository }

    @Environment(ApplicationSettings.self) private var applicationSettings

    private var targetAcresPerHeadDefault: Double { applicationSettings.targetAcresPerHeadDefault }
    private var usableAcreagePercentDefault: Int { applicationSettings.usableAcreagePercentDefault }

    @State private var model = PastureFormViewModel()
    @State private var originatingHerdID: UUID?
    @State private var originatingSelectionRevision: UInt64?

    let onSave: (() -> Void)?

    init(onSave: (() -> Void)? = nil) {
        self.onSave = onSave
    }


    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                Section("Pasture Info") {
                    TextField("Name", text: $model.name)

                    HStack {
                        Text("Acreage")
                        Spacer()
                        TextField("acres", text: $model.acreageText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                }

                if model.shouldShowStockingFields {
                    Section("Stocking") {
                        HStack {
                            Text("Usable Acres")
                            Spacer()
                            TextField("usable acres", text: $model.usableAcreageText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                        }
                        
                        HStack {
                            Text("Target Acres/Head")
                            Spacer()
                            TextField("rate", text: $model.targetAcresPerHeadText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                        }
                    }
                }
            }
            .navigationTitle("Add Pasture")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarSaveButton {
                        save()
                    }
                    .disabled(!model.canSaveNewPasture)
                }

                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton {
                        dismiss()
                    }
                }
            }
            .task {
                if originatingSelectionRevision == nil {
                    originatingHerdID = herdSelection.currentHerdID
                    originatingSelectionRevision = herdSelection.selectionRevision
                }
                model.prepareForCreate(
                    defaultTargetAcresPerHead: targetAcresPerHeadDefault,
                    usableAcreagePercentDefault: usableAcreagePercentDefault
                )
            }
            .alert("Can’t Save", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "Unknown error")
            }
        }
    }

    private func save() {
        do {
            guard let originatingHerdID, let originatingSelectionRevision else {
                throw CancellationError()
            }
            try model.create(
                using: repository,
                defaultTargetAcresPerHead: targetAcresPerHeadDefault,
                usableAcreagePercentDefault: usableAcreagePercentDefault,
                expectedHerdID: originatingHerdID,
                expectedSelectionRevision: originatingSelectionRevision,
                selection: herdSelection
            )
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
