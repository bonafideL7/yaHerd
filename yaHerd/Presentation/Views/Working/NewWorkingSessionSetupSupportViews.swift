import SwiftUI

struct WorkingSessionAnimalSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    let animals: [AnimalSummary]
    @Binding var selection: Set<UUID>
    @State private var searchText = ""

    private var filteredAnimals: [AnimalSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return animals }
        return animals.filter { animal in
            animal.displayTagNumber.localizedCaseInsensitiveContains(query)
                || animal.name.localizedCaseInsensitiveContains(query)
                || tagColorLibrary.formattedTag(tagNumber: animal.displayTagNumber, colorID: animal.displayTagColorID)
                    .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                ForEach(filteredAnimals) { animal in
                    WorkingSessionAnimalSelectionRow(animal: animal).tag(animal.id)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Choose Animals")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search tag or name")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("All") { selection = Set(animals.map(\.id)) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct WorkingSessionAnimalSelectionRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    let animal: AnimalSummary

    var body: some View {
        HStack(spacing: 12) {
            let definition = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)
            let damDefinition = tagColorLibrary.resolvedDefinition(tagColorID: animal.damDisplayTagColorID)
            VStack(alignment: .leading, spacing: 6) {
                AnimalTagView(
                    tagNumber: animal.displayTagNumber,
                    color: definition.color,
                    colorName: definition.name,
                    damTagNumber: animal.damDisplayTagNumber,
                    damTagColor: damDefinition.color,
                    damTagColorName: damDefinition.name,
                    damTagVisibility: animal.animalType == .calf ? .always : .whenUntagged
                )
                Text("\(animal.animalType.label) • \(animal.sex.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct WorkingSessionStartBar: View {
    let animalCount: Int
    let isEnabled: Bool
    let statusText: String?
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let statusText {
                Text(statusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: onStart) {
                Label(
                    animalCount == 1 ? "Start Session with 1 Animal" : "Start Session with \(animalCount) Animals",
                    systemImage: "wrench.and.screwdriver.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!isEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }
}

struct StartedWorkingSessionSetupRoute: Identifiable, Hashable {
    let id: UUID
}
