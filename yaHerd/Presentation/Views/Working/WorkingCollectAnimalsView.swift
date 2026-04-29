//
//  WorkingCollectAnimalsView.swift
//  yaHerd
//

import SwiftUI

struct WorkingCollectAnimalsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let sessionID: UUID

    @State private var session: WorkingSessionDetailSnapshot?
    @State private var availableAnimals: [AnimalSummary] = []
    @State private var selectedAnimalIDs: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var searchText: String = ""

    private var eligibleAnimals: [AnimalSummary] {
        guard let session else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return availableAnimals
            .filter { $0.status == .active && !$0.isArchived }
            .filter { $0.pastureID == session.sourcePastureID }
            .filter { $0.location == .pasture }
            .filter { animal in
                guard !query.isEmpty else { return true }
                return animal.displayTagNumber.localizedCaseInsensitiveContains(query)
                    || tagColorLibrary.formattedTag(tagNumber: animal.displayTagNumber, colorID: animal.displayTagColorID)
                        .localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List(selection: $selectedAnimalIDs) {
                ForEach(eligibleAnimals) { animal in
                    HStack(spacing: 12) {
                        let def = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)
                        let damDef = tagColorLibrary.resolvedDefinition(tagColorID: animal.damDisplayTagColorID)
                        VStack(alignment: .leading, spacing: 6) {
                            AnimalTagView(
                                tagNumber: animal.displayTagNumber,
                                color: def.color,
                                colorName: def.name,
                                damTagNumber: animal.damDisplayTagNumber,
                                damTagColor: damDef.color,
                                damTagColorName: damDef.name
                            )
                            Text(animal.sex.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .tag(animal.id)
                }
            }
            .overlay {
                if session == nil {
                    ProgressView()
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Collect")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search tag")
            .task { load() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        collectSelected()
                    }
                    .disabled(selectedAnimalIDs.isEmpty || session == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Can’t Save", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func load() {
        do {
            session = try dependencies.workingRepository.fetchSessionDetail(id: sessionID)
            availableAnimals = try dependencies.animalRepository.fetchAnimals()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func collectSelected() {
        guard session != nil else { return }
        do {
            let useCase = CollectWorkingAnimalsUseCase(repository: dependencies.workingRepository)
            try useCase.execute(sessionID: sessionID, animalIDs: Array(selectedAnimalIDs))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
