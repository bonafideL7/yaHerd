import SwiftUI

struct AddPastureView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies

    @AppStorage("targetAcresPerHeadDefault") private var targetAcresPerHeadDefault = 3.0
    @AppStorage("usableAcreagePercentDefault") private var usableAcreagePercentDefault = 100

    @State private var model = PastureFormViewModel()

    let onSave: (() -> Void)?

    init(onSave: (() -> Void)? = nil) {
        self.onSave = onSave
    }

    private var repository: any PastureRepository {
        dependencies.pastureRepository
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
                    Button("Save") {
                        save()
                    }
                    .disabled(!model.canSaveNewPasture)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
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
            let input = try model.makeCreateInput(
                defaultTargetAcresPerHead: targetAcresPerHeadDefault,
                usableAcreagePercentDefault: usableAcreagePercentDefault
            )
            _ = try CreatePastureUseCase(repository: repository).execute(input: input)
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
