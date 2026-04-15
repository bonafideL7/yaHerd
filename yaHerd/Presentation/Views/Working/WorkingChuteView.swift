import SwiftUI

struct WorkingChuteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @StateObject private var viewModel: WorkingQueueItemEditorViewModel

    @State private var treatEntries: [TreatmentEntry] = []
    @State private var observationNotes: String = ""
    @State private var pregResult: PregnancyResult = .unknown
    @State private var estimatedDaysText: String = ""
    @State private var dueDate: Date = .now
    @State private var selectedSire: AnimalParentOption?
    @State private var markCastrated: Bool = false
    @State private var showingSirePicker = false
    @State private var errorMessage: String?
    @State private var showingError = false

    init(sessionID: UUID, queueItemID: UUID) {
        _viewModel = StateObject(wrappedValue: WorkingQueueItemEditorViewModel(sessionID: sessionID, queueItemID: queueItemID, workingRepository: EmptyWorkingRepository(), animalRepository: EmptyAnimalRepository()))
    }

    private var snapshot: WorkingQueueItemEditorSnapshot? { viewModel.snapshot }

    private var isFemale: Bool {
        snapshot?.animalSex == .female
    }

    private var isMale: Bool {
        snapshot?.animalSex == .male
    }

    private var showPregSection: Bool {
        guard let snapshot else { return false }
        return isFemale && snapshot.animalAgeInMonths >= WorkingConstants.pregCheckEligibleMonths
    }

    private var showCastrationSection: Bool {
        snapshot != nil && isMale
    }

    var body: some View {
        Form {
            Section {
                if let snapshot, let tagNumber = snapshot.animalDisplayTagNumber {
                    HStack {
                        let def = tagColorLibrary.resolvedDefinition(tagColorID: snapshot.animalDisplayTagColorID)
                        AnimalTagView(
                            tagNumber: tagNumber,
                            color: def.color,
                            colorName: def.name,
                            size: .prominent
                        )
                        Spacer()
                        Text(snapshot.animalSex.label)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Missing animal")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Protocol") {
                if treatEntries.isEmpty {
                    Text("No protocol items")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(treatEntries.indices, id: \.self) { idx in
                        let name = treatEntries[idx].name
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(name, isOn: $treatEntries[idx].given)
                            HStack {
                                Text("Quantity")
                                Spacer()
                                TextField("", text: $treatEntries[idx].quantityText)
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 120)
                            }
                        }
                    }
                }
            }

            if showPregSection {
                Section("Preg Check") {
                    Picker("Result", selection: $pregResult) {
                        ForEach(PregnancyResult.allCases, id: \.self) { value in
                            Text(value.rawValue.capitalized).tag(value)
                        }
                    }

                    if pregResult == .pregnant {
                        HStack {
                            Text("Est. days")
                            Spacer()
                            TextField("", text: $estimatedDaysText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                                .frame(width: 120)
                        }

                        DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)

                        Button {
                            showingSirePicker = true
                        } label: {
                            HStack {
                                Text("Sire")
                                Spacer()
                                if let selectedSire {
                                    let def = tagColorLibrary.resolvedDefinition(tagColorID: selectedSire.displayTagColorID)
                                    AnimalTagView(
                                        tagNumber: selectedSire.displayTagNumber,
                                        color: def.color,
                                        colorName: def.name,
                                        size: .compact
                                    )
                                } else {
                                    Text("Choose")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            if showCastrationSection {
                Section("Castration") {
                    Toggle("Mark Castrated", isOn: $markCastrated)
                }
            }

            Section("Observations") {
                TextField("Notes", text: $observationNotes, axis: .vertical)
            }
        }
        .navigationTitle("Work")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    complete()
                }
                .disabled(snapshot?.animalID == nil)
            }
        }
        .task {
            viewModel.configure(workingRepository: dependencies.workingRepository, animalRepository: dependencies.animalRepository)
            viewModel.load()
            seedState()
        }
        .onChange(of: viewModel.snapshot?.id) { _, _ in
            seedState()
        }
        .onChange(of: estimatedDaysText) { _, _ in
            recalcDueDate()
        }
        .sheet(isPresented: $showingSirePicker) {
            sirePickerSheet
        }
        .alert("Can’t Save", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? viewModel.errorMessage ?? "")
        }
    }

    private var sirePickerSheet: some View {
        AnimalParentPickerView(
            title: "Select Sire",
            excludeAnimalID: snapshot?.animalID,
            suggestedSexes: [.male]
        ) { picked in
            selectedSire = picked
        }
    }

    private func seedState() {
        guard let snapshot, treatEntries.isEmpty else { return }
        treatEntries = snapshot.protocolItems.map { item in
            let existing = snapshot.treatmentRecords.first(where: { $0.itemName == item.name })
            return TreatmentEntry(
                id: item.id,
                name: item.name,
                given: existing?.given ?? true,
                quantityText: existing?.quantity.map { "\($0)" } ?? item.defaultQuantity.map { "\($0)" } ?? ""
            )
        }
        pregResult = snapshot.pregnancyCheck?.result ?? .unknown
        estimatedDaysText = snapshot.pregnancyCheck?.estimatedDaysPregnant.map { "\($0)" } ?? ""
        dueDate = snapshot.pregnancyCheck?.dueDate ?? snapshot.sessionDate
        selectedSire = snapshot.pregnancyCheck?.sire
        markCastrated = snapshot.castrationPerformedInSession
        observationNotes = snapshot.observationNotes
    }

    private func recalcDueDate() {
        guard pregResult == .pregnant else { return }
        guard let est = Int(estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let remaining = max(0, WorkingConstants.gestationDays - est)
        if let computed = Calendar.current.date(byAdding: .day, value: remaining, to: .now) {
            dueDate = computed
        }
    }

    private func complete() {
        guard let snapshot else { return }

        let treatmentInputs = treatEntries.map { entry in
            WorkingTreatmentEntryInput(
                date: .now,
                itemName: entry.name,
                given: entry.given,
                quantity: Double(entry.quantityText.trimmingCharacters(in: .whitespacesAndNewlines))
            )
        }

        let pregnancyInput: WorkingPregnancyCheckInput?
        if showPregSection, pregResult == .open || pregResult == .pregnant {
            pregnancyInput = WorkingPregnancyCheckInput(
                date: .now,
                result: pregResult,
                estimatedDaysPregnant: Int(estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)),
                dueDate: pregResult == .pregnant ? dueDate : nil,
                sireAnimalID: selectedSire?.id
            )
        } else {
            pregnancyInput = nil
        }

        do {
            let useCase = CompleteWorkingQueueItemUseCase(repository: dependencies.workingRepository)
            try useCase.execute(
                queueItemID: snapshot.id,
                sessionID: snapshot.sessionID,
                treatmentEntries: treatmentInputs,
                pregnancyCheck: pregnancyInput,
                markCastrated: markCastrated,
                observationNotes: observationNotes
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

private struct TreatmentEntry: Identifiable {
    let id: UUID
    var name: String
    var given: Bool
    var quantityText: String
}
