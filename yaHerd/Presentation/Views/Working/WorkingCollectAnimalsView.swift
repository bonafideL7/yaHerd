//
//  WorkingCollectAnimalsView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

struct WorkingCollectAnimalsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @Bindable var session: WorkingSession

    @Query(sort: \Animal.tagNumber) private var animals: [Animal]

    @State private var selected: Set<Animal> = []
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var searchText: String = ""

    private var eligibleAnimals: [Animal] {
        let src = session.sourcePasture
        return animals
            .filter { $0.isActiveInHerd }
            .filter { $0.pasture === src }
            .filter { $0.location == .pasture }
            .filter { animal in
                guard !searchText.isEmpty else { return true }
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                return animal.tagNumber.localizedCaseInsensitiveContains(q)
                    || tagColorLibrary.formattedTag(for: animal).localizedCaseInsensitiveContains(q)
            }
    }

    var body: some View {
        NavigationStack {
            List(selection: $selected) {
                ForEach(eligibleAnimals) { animal in
                    HStack(spacing: 12) {
                        let def = tagColorLibrary.resolvedDefinition(for: animal)
                        VStack(alignment: .leading, spacing: 6) {
                            AnimalTagView(
                                tagNumber: animal.tagNumber,
                                color: def.color,
                                colorName: def.name
                            )
                            Text((animal.sex ?? .female).label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .tag(animal)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Collect")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search tag")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        collectSelected()
                    }
                    .disabled(selected.isEmpty)
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

    private func collectSelected() {
        do {
            let repository = SwiftDataWorkingRepository(context: context)
            let useCase = CollectWorkingAnimalsUseCase(repository: repository)
            try useCase.execute(session: session, animals: Array(selected))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
