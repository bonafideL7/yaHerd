import SwiftUI

struct PasturePickerView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss

    @State private var pastureOptions: [PastureOption] = []

    let animalID: UUID
    let currentPastureID: UUID?

    @State private var model = PastureChangeViewModel()
    @State private var showingError = false

    private var repository: any AnimalRepository {
        dependencies.animalRepository
    }

    init(animalID: UUID, currentPastureID: UUID? = nil) {
        self.animalID = animalID
        self.currentPastureID = currentPastureID
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Assign Pasture") {
                    Picker(
                        "Pasture",
                        selection: Binding(
                            get: { model.selectedPastureID },
                            set: { model.selectedPastureID = $0 }
                        )
                    ) {
                        Text("None")
                            .tag(UUID?.none)

                        ForEach(pastureOptions) { pasture in
                            Text(pasture.name)
                                .tag(Optional(pasture.id))
                        }
                    }
                }
            }
            .navigationTitle("Change Pasture")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.moveAnimal(animalID: animalID, using: repository) {
                            dismiss()
                        } else {
                            showingError = true
                        }
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                model.selectedPastureID = currentPastureID
                do {
                    pastureOptions = try repository.fetchPastureOptions()
                } catch {
                    model.errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            .alert("Can’t Save", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}
