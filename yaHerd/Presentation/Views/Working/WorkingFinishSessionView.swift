import SwiftUI

struct WorkingFinishSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @StateObject private var viewModel: WorkingFinishSessionViewModel

    @State private var destinationPastureIDs: [UUID: UUID?] = [:]
    @State private var errorMessage: String?
    @State private var showingError = false

    init(sessionID: UUID) {
        _viewModel = StateObject(wrappedValue: WorkingFinishSessionViewModel(sessionID: sessionID, workingRepository: EmptyWorkingRepository(), animalRepository: EmptyAnimalRepository()))
    }

    private var session: WorkingSessionDetailSnapshot? {
        viewModel.session
    }

    private var orderedItems: [WorkingQueueItemSnapshot] {
        session?.queueItems.sorted { $0.queueOrder < $1.queueOrder } ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Return") {
                    Text("Assign a destination pasture for each animal, then return them out of the working pen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Animals") {
                    ForEach(orderedItems) { item in
                        if let tagNumber = item.animalDisplayTagNumber {
                            HStack {
                                let def = tagColorLibrary.resolvedDefinition(tagColorID: item.animalDisplayTagColorID)
                let damDef = tagColorLibrary.resolvedDefinition(tagColorID: item.animalDamDisplayTagColorID)
                                AnimalTagView(
                                    tagNumber: tagNumber,
                                    color: def.color,
                                    colorName: def.name,
                                    size: .compact,
                                    damTagNumber: item.animalDamDisplayTagNumber,
                                    damTagColor: damDef.color,
                                    damTagColorName: damDef.name
                                )
                                Spacer()
                                Picker("", selection: bindingDestination(for: item)) {
                                    Text("None").tag(Optional<UUID>(nil))
                                    ForEach(viewModel.pastures) { pasture in
                                        Text(pasture.name).tag(Optional(pasture.id))
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Finish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Return") { returnAnimals() }
                        .disabled(session == nil)
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button("All to Source") { assignAllToSource() }
                        .disabled(session?.sourcePastureID == nil)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                viewModel.configure(workingRepository: dependencies.workingRepository, animalRepository: dependencies.animalRepository)
                viewModel.load()
                seedDestinations()
            }
            .onChange(of: viewModel.session?.id) { _, _ in
                seedDestinations(force: true)
            }
            .alert("Can’t Save", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? viewModel.errorMessage ?? "")
            }
        }
    }

    private func seedDestinations(force: Bool = false) {
        guard let session else { return }
        if !force && !destinationPastureIDs.isEmpty { return }
        destinationPastureIDs = Dictionary(uniqueKeysWithValues: session.queueItems.map {
            ($0.id, $0.destinationPastureID ?? session.sourcePastureID)
        })
    }

    private func bindingDestination(for item: WorkingQueueItemSnapshot) -> Binding<UUID?> {
        Binding<UUID?>(
            get: { destinationPastureIDs[item.id] ?? item.destinationPastureID ?? session?.sourcePastureID },
            set: { newValue in destinationPastureIDs[item.id] = newValue }
        )
    }

    private func assignAllToSource() {
        guard let sourcePastureID = session?.sourcePastureID else { return }
        for item in orderedItems {
            destinationPastureIDs[item.id] = sourcePastureID
        }
    }

    private func returnAnimals() {
        guard let session else { return }
        let assignments = orderedItems.map {
            WorkingQueueDestinationAssignment(queueItemID: $0.id, destinationPastureID: destinationPastureIDs[$0.id] ?? $0.destinationPastureID ?? session.sourcePastureID)
        }
        do {
            let saveUseCase = SaveWorkingDestinationsUseCase(repository: dependencies.workingRepository)
            try saveUseCase.execute(sessionID: session.id, assignments: assignments)
            let finishUseCase = FinishWorkingSessionUseCase(repository: dependencies.workingRepository)
            try finishUseCase.execute(sessionID: session.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
