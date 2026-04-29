import SwiftUI

struct WorkingSessionAnimalEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var viewModel: WorkingQueueItemEditorViewModel

    @State private var status: WorkingQueueStatus = .queued
    @State private var completedAt: Date = .now
    @State private var destinationPastureID: UUID?
    @State private var treatmentEntries: [TreatmentEditEntry] = []
    @State private var recordPregCheck = false
    @State private var pregResult: PregnancyResult = .unknown
    @State private var pregDate: Date = .now
    @State private var estimatedDaysText: String = ""
    @State private var dueDate: Date = .now
    @State private var selectedSire: AnimalParentOption?
    @State private var showingSirePicker = false
    @State private var castrationPerformedInSession = false
    @State private var observationNotes: String = ""
    @State private var errorMessage: String?
    @State private var showingError = false

    init(sessionID: UUID, queueItemID: UUID) {
        _viewModel = StateObject(wrappedValue: WorkingQueueItemEditorViewModel(sessionID: sessionID, queueItemID: queueItemID, workingRepository: EmptyWorkingRepository(), animalRepository: EmptyAnimalRepository()))
    }

    private var snapshot: WorkingQueueItemEditorSnapshot? { viewModel.snapshot }

    private var isFemale: Bool {
        snapshot?.animalSex == .female
    }

    private var showPregSection: Bool {
        guard let snapshot else { return false }
        return isFemale && snapshot.animalAgeInMonths >= WorkingConstants.pregCheckEligibleMonths
    }

    var body: some View {
        Form {
            Section {
                if let snapshot, let tagNumber = snapshot.animalDisplayTagNumber {
                    HStack {
                        let def = tagColorLibrary.resolvedDefinition(tagColorID: snapshot.animalDisplayTagColorID)
                        let damDef = tagColorLibrary.resolvedDefinition(tagColorID: snapshot.animalDamDisplayTagColorID)
                        AnimalTagView(
                            tagNumber: tagNumber,
                            color: def.color,
                            colorName: def.name,
                            size: .prominent,
                            damTagNumber: snapshot.animalDamDisplayTagNumber,
                            damTagColor: damDef.color,
                            damTagColorName: damDef.name
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

            Section("Queue") {
                Picker("Status", selection: $status) {
                    ForEach(WorkingQueueStatus.allCases, id: \.self) { value in
                        Text(value.rawValue.capitalized).tag(value)
                    }
                }

                if status == .done {
                    DatePicker("Completed", selection: $completedAt, displayedComponents: [.date, .hourAndMinute])
                }

                if let source = snapshot?.collectedFromPastureName ?? snapshot?.sessionSourcePastureName {
                    LabeledContent("Collected from", value: source)
                }

                Picker("Destination", selection: $destinationPastureID) {
                    Text("None").tag(Optional<UUID>(nil))
                    ForEach(viewModel.pastures) { pasture in
                        Text(pasture.name).tag(Optional(pasture.id))
                    }
                }
            }

            Section("Treatments") {
                if treatmentEntries.isEmpty {
                    Text("No protocol items")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(treatmentEntries.indices, id: \.self) { idx in
                        let entry = treatmentEntries[idx]
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(entry.name, isOn: $treatmentEntries[idx].given)
                            HStack {
                                Text("Quantity")
                                Spacer()
                                TextField("", text: $treatmentEntries[idx].quantityText)
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 120)
                            }
                            DatePicker("Date", selection: $treatmentEntries[idx].date, displayedComponents: [.date])
                                .font(.caption)
                        }
                    }
                }
            }

            if showPregSection {
                Section("Preg Check") {
                    Toggle("Record preg check", isOn: $recordPregCheck)

                    if recordPregCheck {
                        DatePicker("Date", selection: $pregDate, displayedComponents: [.date])

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
                            DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date])

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
            }

            Section("Procedures") {
                Toggle("Castration performed (this session)", isOn: $castrationPerformedInSession)
                    .disabled(snapshot?.animalID == nil)
            }

            Section("Observations") {
                TextField("Notes", text: $observationNotes, axis: .vertical)
            }

            Section {
                Button(role: .destructive) {
                    deleteWorkDataForAnimal()
                } label: {
                    Text("Delete this animal's work data")
                }
                .disabled(snapshot?.animalID == nil)
            } footer: {
                Text("Deletes treatments, preg checks, and session-tied records for this animal in this session. It does not delete movement or status history.")
            }
        }
        .navigationTitle("Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(snapshot?.animalID == nil)
            }
        }
        .task {
            viewModel.configure(workingRepository: dependencies.workingRepository, animalRepository: dependencies.animalRepository)
            viewModel.load()
            seedState()
        }
        .onChange(of: viewModel.snapshot?.id) { _, _ in
            seedState(force: true)
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

    private func seedState(force: Bool = false) {
        guard let snapshot else { return }
        if !force && !treatmentEntries.isEmpty { return }

        let grouped = Dictionary(grouping: snapshot.treatmentRecords, by: { $0.itemName })
        treatmentEntries = snapshot.protocolItems.map { item in
            let existing = grouped[item.name]?.sorted(by: { $0.date > $1.date }).first
            return TreatmentEditEntry(
                id: item.id,
                name: item.name,
                given: existing?.given ?? true,
                quantityText: existing?.quantity.map { "\($0)" } ?? item.defaultQuantity.map { "\($0)" } ?? "",
                date: existing?.date ?? snapshot.sessionDate
            )
        }

        status = snapshot.status
        completedAt = snapshot.completedAt ?? snapshot.sessionDate
        destinationPastureID = snapshot.destinationPastureID
        recordPregCheck = snapshot.pregnancyCheck != nil
        pregResult = snapshot.pregnancyCheck?.result ?? .unknown
        pregDate = snapshot.pregnancyCheck?.date ?? snapshot.sessionDate
        estimatedDaysText = snapshot.pregnancyCheck?.estimatedDaysPregnant.map { "\($0)" } ?? ""
        dueDate = snapshot.pregnancyCheck?.dueDate ?? snapshot.sessionDate
        selectedSire = snapshot.pregnancyCheck?.sire
        castrationPerformedInSession = snapshot.castrationPerformedInSession
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

    private func save() {
        guard let snapshot else { return }

        let pregnancyInput: WorkingPregnancyCheckInput?
        if showPregSection && recordPregCheck && (pregResult == .open || pregResult == .pregnant) {
            pregnancyInput = WorkingPregnancyCheckInput(
                date: pregDate,
                result: pregResult,
                estimatedDaysPregnant: Int(estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)),
                dueDate: pregResult == .pregnant ? dueDate : nil,
                sireAnimalID: selectedSire?.id
            )
        } else {
            pregnancyInput = nil
        }

        let input = WorkingSessionAnimalEditInput(
            status: status,
            completedAt: status == .done ? completedAt : nil,
            destinationPastureID: destinationPastureID,
            treatmentEntries: treatmentEntries.map {
                WorkingTreatmentEntryInput(
                    date: $0.date,
                    itemName: $0.name,
                    given: $0.given,
                    quantity: Double($0.quantityText.trimmingCharacters(in: .whitespacesAndNewlines))
                )
            },
            pregnancyCheck: pregnancyInput,
            castrationPerformed: castrationPerformedInSession,
            observationNotes: observationNotes
        )

        do {
            let useCase = SaveWorkingQueueItemEditsUseCase(repository: dependencies.workingRepository)
            try useCase.execute(queueItemID: snapshot.id, sessionID: snapshot.sessionID, input: input)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func deleteWorkDataForAnimal() {
        guard let snapshot else { return }
        do {
            let useCase = DeleteWorkingQueueItemDataUseCase(repository: dependencies.workingRepository)
            try useCase.execute(queueItemID: snapshot.id, sessionID: snapshot.sessionID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

private struct TreatmentEditEntry: Identifiable {
    let id: UUID
    var name: String
    var given: Bool
    var quantityText: String
    var date: Date
}
