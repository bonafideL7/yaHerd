//
//  WorkingChuteView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

struct WorkingChuteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let session: WorkingSession
    @Bindable var queueItem: WorkingQueueItem

    @State private var treatEntries: [TreatmentEntry] = []
    @State private var observationNotes: String = ""

    // Preg check
    @State private var pregResult: PregnancyResult = .unknown
    @State private var estimatedDaysText: String = ""
    @State private var dueDate: Date = .now
    @State private var selectedSire: Animal?

    // Male procedure
    @State private var markCastrated: Bool = false

    private var animal: Animal? { queueItem.animal }

    private var isFemale: Bool {
        guard let animal else { return false }
        return animal.designation == .cow || animal.designation == .heifer
    }

    private var isMale: Bool {
        guard let animal else { return false }
        return animal.designation == .bull || animal.designation == .steer
    }

    private var showPregSection: Bool {
        guard let animal else { return false }
        return isFemale && animal.ageInMonths >= WorkingConstants.pregCheckEligibleMonths
    }

    private var showCastrationSection: Bool {
        guard let animal else { return false }
        return isMale && (animal.biologicalSex ?? animal.sex.inferredBiologicalSex) == .male && !animal.isCastrated
    }

    var body: some View {
        Form {
            Section {
                if let animal {
                    HStack {
                        TagColorDot(tagColor: animal.tagColor ?? .yellow)
                        Text("Tag \(animal.tagNumber)")
                            .font(.title2.bold())
                        Spacer()
                        Text(animal.designation.rawValue.capitalized)
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
                        ForEach(PregnancyResult.allCases, id: \.self) { v in
                            Text(v.rawValue.capitalized).tag(v)
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
                            // reuse existing picker UI
                            showingSirePicker = true
                        } label: {
                            HStack {
                                Text("Sire")
                                Spacer()
                                Text(selectedSire?.tagNumber ?? "Choose")
                                    .foregroundStyle(selectedSire == nil ? .secondary : .primary)
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
    }

    @State private var showingSirePicker: Bool = false

    private var sirePickerSheet: some View {
        AnimalParentPickerView(
            title: "Select Sire",
            excludeAnimal: animal,
            suggestedSexes: [.bull]
        ) { picked in
            selectedSire = picked
        }
    }

    private func seedState() {
        // Initialize protocol items for this session
        if treatEntries.isEmpty {
            treatEntries = session.protocolItems.map { item in
                TreatmentEntry(
                    id: item.id,
                    name: item.name,
                    given: true,
                    // Avoid ambiguous overload resolution on String.init
                    quantityText: item.defaultQuantity.map { "\($0)" } ?? ""
                )
            }
        }

        // Default preg check state
        pregResult = .unknown
        estimatedDaysText = ""
        dueDate = Date()
        selectedSire = nil
        markCastrated = false
    }

    private func recalcDueDate() {
        guard pregResult == .pregnant else { return }
        let checkDate = Date()
        guard let est = Int(estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }

        let remaining = max(0, WorkingConstants.gestationDays - est)
        if let computed = Calendar.current.date(byAdding: .day, value: remaining, to: checkDate) {
            dueDate = computed
        }
    }

    private func complete() {
        guard let animal else { return }

        let sid = session.persistentModelID
        let aid = animal.persistentModelID

        queueItem.status = .done
        queueItem.completedAt = .now

        // Upsert treatment completion for this animal+session (avoid duplicates if re-worked)
        // NOTE: SwiftData predicate macros are unreliable when comparing relationship values.
        // Fetch and filter in-memory instead.
        if let existing = try? context.fetch(FetchDescriptor<WorkingTreatmentRecord>()) {
            for rec in existing where rec.session?.persistentModelID == sid && rec.animal?.persistentModelID == aid {
                context.delete(rec)
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

        // Preg check capture (only if user set Open/Pregnant). Upsert for this session+animal.
        if showPregSection {
            if let existingChecks = try? context.fetch(FetchDescriptor<PregnancyCheck>()) {
                for c in existingChecks where c.workingSession?.persistentModelID == sid && c.animal.persistentModelID == aid {
                    context.delete(c)
                }
            }

            if pregResult == .open || pregResult == .pregnant {
                let estDays = Int(estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines))
                let computedDue: Date? = (pregResult == .pregnant) ? dueDate : nil

                let check = PregnancyCheck(
                    date: .now,
                    result: pregResult,
                    technician: nil,
                    estimatedDaysPregnant: estDays,
                    dueDate: computedDue,
                    sireAnimal: selectedSire,
                    workingSession: session,
                    animal: animal
                )
                context.insert(check)
            }
        }

        // Castration
        if markCastrated {
            animal.isCastrated = true
            animal.syncLegacySexFromData()
            // Upsert a castration record tied to this session.
            if let existing = try? context.fetch(FetchDescriptor<HealthRecord>()) {
                for r in existing where r.workingSession?.persistentModelID == sid
                    && r.animal.persistentModelID == aid
                    && r.treatment == "Castration" {
                    context.delete(r)
                }
            }
            let record = HealthRecord(date: .now, treatment: "Castration", notes: nil, workingSession: session, animal: animal)
            context.insert(record)
        }

        // Observations
        let trimmedObs = observationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedObs.isEmpty {
            // Upsert a single observation record tied to this session.
            if let existing = try? context.fetch(FetchDescriptor<HealthRecord>()) {
                for r in existing where r.workingSession?.persistentModelID == sid
                    && r.animal.persistentModelID == aid
                    && r.treatment == "Observation" {
                    context.delete(r)
                }
            }
            let record = HealthRecord(date: .now, treatment: "Observation", notes: trimmedObs, workingSession: session, animal: animal)
            context.insert(record)
        }

        try? context.save()
        dismiss()
    }
}

private struct TreatmentEntry: Identifiable {
    let id: UUID
    var name: String
    var given: Bool
    var quantityText: String
}
