//
//  WorkingChuteView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

struct WorkingChuteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let session: WorkingSession
    @Bindable var queueItem: WorkingQueueItem

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

    private var animal: Animal? { queueItem.animal }

    private var isFemale: Bool {
        guard let animal else { return false }
        return (animal.sex ?? .female) == .female
    }

    private var isMale: Bool {
        guard let animal else { return false }
        return (animal.sex ?? .female) == .male
    }

    private var showPregSection: Bool {
        guard let animal else { return false }
        return isFemale && animal.ageInMonths >= WorkingConstants.pregCheckEligibleMonths
    }

    private var showCastrationSection: Bool {
        guard animal != nil else { return false }
        return isMale
    }

    var body: some View {
        Form {
            Section {
                if let animal {
                    HStack {
                        let def = tagColorLibrary.resolvedDefinition(for: animal)
                        AnimalTagView(
                            tagNumber: animal.tagNumber,
                            color: def.color,
                            colorName: def.name,
                            size: .prominent
                        )
                        Spacer()
                        Text((animal.sex ?? .female).label)
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
                .disabled(animal == nil)
            }
        }
        .onAppear {
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
            Text(errorMessage ?? "")
        }
    }

    private var sirePickerSheet: some View {
        AnimalParentPickerView(
            title: "Select Sire",
            excludeAnimalID: animal?.publicID,
            suggestedSexes: [.male]
        ) { picked in
            selectedSire = picked
        }
    }

    private func seedState() {
        if treatEntries.isEmpty {
            treatEntries = session.protocolItems.map { item in
                TreatmentEntry(
                    id: item.id,
                    name: item.name,
                    given: true,
                    quantityText: item.defaultQuantity.map { "\($0)" } ?? ""
                )
            }
        }

        pregResult = .unknown
        estimatedDaysText = ""
        dueDate = .now
        selectedSire = nil
        markCastrated = false
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
        guard animal != nil else { return }

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
            let repository = SwiftDataWorkingRepository(context: context)
            let useCase = CompleteWorkingQueueItemUseCase(repository: repository)
            try useCase.execute(
                queueItem: queueItem,
                session: session,
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
