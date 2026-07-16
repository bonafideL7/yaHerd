import SwiftUI

struct PasturePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pastureFeatureDependencies) private var pastureDependencies
    private var animalMover: any AnimalPastureMoving { pastureDependencies.animalMover }
    private var pastureReferenceReader: any PastureReferenceDataReader { pastureDependencies.referenceReader }

    @State private var pastureOptions: [PastureOption] = []

    let animalID: UUID
    let currentPastureID: UUID?

    @State private var model = PastureChangeViewModel()
    @State private var showingError = false


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
                    ToolbarSaveButton {
                        if model.moveAnimal(animalID: animalID, using: animalMover) {
                            dismiss()
                        } else {
                            showingError = true
                        }
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                }
            }
            .task {
                model.selectedPastureID = currentPastureID
                do {
                    pastureOptions = try pastureReferenceReader.fetchPastureOptions()
                } catch {
                    model.errorMessage = UserVisibleErrorMessage.make(error)
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
