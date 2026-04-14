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
        guard let animal else { return }

        let sid = session.persistentModelID
        let aid = animal.persistentModelID

        queueItem.status = .done
        queueItem.completedAt = .now

        if let existing = try? context.fetch(FetchDescriptor<WorkingTreatmentRecord>()) {
            for record in existing where record.session?.persistentModelID == sid && record.animal?.persistentModelID == aid {
                context.delete(record)
            }
        }
        for entry in treatEntries {
            let qty = Double(entry.quantityText.trimmingCharacters(in: .whitespacesAndNewlines))
            let record = WorkingTreatmentRecord(
                date: .now,
                itemName: entry.name,
                given: entry.given,
                quantity: qty,
                animal: animal,
                session: session
            )
            context.insert(record)
        }

        if showPregSection {
            if let existingChecks = try? context.fetch(FetchDescriptor<PregnancyCheck>()) {
                for check in existingChecks where check.workingSession?.persistentModelID == sid && check.animal.persistentModelID == aid {
                    context.delete(check)
                }
            }

            if pregResult == .open || pregResult == .pregnant {
                let estDays = Int(estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines))
                let computedDue: Date? = pregResult == .pregnant ? dueDate : nil

                let check = PregnancyCheck(
                    date: .now,
                    result: pregResult,
                    technician: nil,
                    estimatedDaysPregnant: estDays,
                    dueDate: computedDue,
                    sireAnimal: resolveAnimal(publicID: selectedSire?.id),
                    workingSession: session,
                    animal: animal
                )
                context.insert(check)
            }
        }

        if markCastrated {
            if let existing = try? context.fetch(FetchDescriptor<HealthRecord>()) {
                for record in existing where record.workingSession?.persistentModelID == sid
                    && record.animal.persistentModelID == aid
                    && record.treatment == "Castration" {
                    context.delete(record)
                }
            }

            let record = HealthRecord(
                date: .now,
                treatment: "Castration",
                notes: nil,
                workingSession: session,
                animal: animal
            )
            context.insert(record)
        }

        let trimmedObs = observationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedObs.isEmpty {
            if let existing = try? context.fetch(FetchDescriptor<HealthRecord>()) {
                for record in existing where record.workingSession?.persistentModelID == sid
                    && record.animal.persistentModelID == aid
                    && record.treatment == "Observation" {
                    context.delete(record)
                }
            }

            let record = HealthRecord(
                date: .now,
                treatment: "Observation",
                notes: trimmedObs,
                workingSession: session,
                animal: animal
            )
            context.insert(record)
        }

        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func resolveAnimal(publicID: UUID?) -> Animal? {
        guard let publicID else { return nil }
        let descriptor = FetchDescriptor<Animal>(
            predicate: #Predicate<Animal> { animal in
                animal.publicID == publicID
            }
        )
        return try? context.fetch(descriptor).first
    }
}

private struct TreatmentEntry: Identifiable {
    let id: UUID
    var name: String
    var given: Bool
    var quantityText: String
}
