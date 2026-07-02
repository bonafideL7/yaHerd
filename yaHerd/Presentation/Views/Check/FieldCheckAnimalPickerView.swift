import SwiftUI

struct FieldCheckLinkedAnimalSelectorRow: View {
    let animals: [FieldCheckAnimalCheckSnapshot]
    @Binding var selectedAnimalID: UUID?

    private var selectedAnimal: FieldCheckAnimalCheckSnapshot? {
        guard let selectedAnimalID else { return nil }
        return animals.first { $0.animalID == selectedAnimalID }
    }

    var body: some View {
        NavigationLink {
            FieldCheckAnimalPickerView(
                animals: animals,
                selectedAnimalID: $selectedAnimalID
            )
        } label: {
            LabeledContent("Linked Animal") {
                FieldCheckSelectedAnimalLabel(animal: selectedAnimal)
            }
        }
    }
}

struct FieldCheckAnimalPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let animals: [FieldCheckAnimalCheckSnapshot]
    @Binding var selectedAnimalID: UUID?

    var body: some View {
        List {
            Section {
                Button {
                    selectedAnimalID = nil
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text("None")
                            .foregroundStyle(.primary)

                        Spacer(minLength: 12)

                        if selectedAnimalID == nil {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            Section {
                ForEach(animals) { animal in
                    Button {
                        selectedAnimalID = animal.animalID
                        dismiss()
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            FieldCheckAnimalPickerRow(animal: animal)

                            if selectedAnimalID == animal.animalID {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .fixedSize()
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Roster Animals")
            } footer: {
                Text("Animals are shown with check-specific status and type details instead of pasture or birth date metadata.")
            }
        }
        .navigationTitle("Linked Animal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FieldCheckSelectedAnimalLabel: View {
    let animal: FieldCheckAnimalCheckSnapshot?

    var body: some View {
        if let animal {
            Text(selectionTitle(for: animal))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("None")
                .foregroundStyle(.secondary)
        }
    }

    private func selectionTitle(for animal: FieldCheckAnimalCheckSnapshot) -> String {
        let trimmedName = animal.animalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedName.isEmpty ? animal.displayTagNumber : "\(animal.displayTagNumber) • \(trimmedName)"
        return "\(base) • \(animal.animalType.label)"
    }
}

private struct FieldCheckAnimalPickerRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let animal: FieldCheckAnimalCheckSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                animalTag
                primaryInfoPill
            }

            VStack(alignment: .trailing, spacing: 8) {
                FieldCheckAnimalPickerStatusPills(animal: animal)
                typeAndSexPill
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var animalTag: some View {
        let definition = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)
        let damDefinition = tagColorLibrary.resolvedDefinition(tagColorID: animal.damDisplayTagColorID)

        return AnimalTagView(
            tagNumber: animal.displayTagNumber,
            color: definition.color,
            colorName: definition.name,
            damTagNumber: animal.damDisplayTagNumber,
            damTagColor: damDefinition.color,
            damTagColorName: damDefinition.name,
            damTagVisibility: animal.animalType == .calf ? .always : .whenUntagged
        )
    }

    private var primaryInfoPill: some View {
        let trimmedName = animal.animalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedName.isEmpty ? animal.animalType.label : trimmedName

        return AnimalListInfoPill(title: title, systemImage: "")
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var typeAndSexPill: some View {
        AnimalListInfoPill(
            title: "\(animal.animalType.label) • \(animal.animalSex.label)",
            systemImage: "tag"
        )
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct FieldCheckAnimalPickerStatusPills: View {
    let animal: FieldCheckAnimalCheckSnapshot

    var body: some View {
        HStack(spacing: 6) {
            if animal.isMissing {
                FieldCheckBadge(title: "Missing", tint: .orange)
            }

            if animal.wasCounted {
                FieldCheckBadge(title: "Counted", tint: .green)
            }

            if animal.needsAttention {
                FieldCheckBadge(title: "Flagged", tint: .orange)
            }

            if !animal.isMissing && !animal.wasCounted && !animal.needsAttention {
                FieldCheckBadge(title: "Expected", tint: .secondary)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct FieldCheckTrackedAnimalPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.animalListRepository) private var animalRepository

    @State private var model = FieldCheckTrackedAnimalPickerViewModel()

    let session: FieldCheckSessionDetailSnapshot
    let onSelect: (UUID) -> Bool

    private var existingAnimalIDs: Set<UUID> {
        Set(session.animalChecks.compactMap(\.animalID))
    }

    private var eligibleAnimals: [AnimalSummary] {
        model.eligibleAnimals(
            forPastureID: session.pastureID,
            excluding: existingAnimalIDs
        )
    }

    private var destinationName: String {
        session.pastureName ?? "this pasture"
    }

    var body: some View {
        List {
            Section {
                if eligibleAnimals.isEmpty {
                    ContentUnavailableView(
                        "No Tracked Animals",
                        systemImage: "tag",
                        description: Text("No active tracked herd animals from other pastures match this search.")
                    )
                } else {
                    ForEach(eligibleAnimals) { animal in
                        Button {
                            if onSelect(animal.id) {
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                AnimalListRowContent(animal: animal)

                                Text(moveSummary(for: animal))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Tracked Herd Animals")
            } footer: {
                Text("Selecting an animal moves it to \(destinationName), records a pasture movement, adds it to this check, and marks it checked. Use Add Offspring from the dam record for new calves.")
            }
        }
        .navigationTitle("Add to Pasture")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.searchText, prompt: "Search animals")
        .task {
            if !model.hasLoaded {
                model.load(using: animalRepository)
            }
        }
        .alert("Can’t Load Animals", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private func moveSummary(for animal: AnimalSummary) -> String {
        let fromName = animal.pastureName ?? "No pasture"
        return "Move from \(fromName) to \(destinationName)"
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
