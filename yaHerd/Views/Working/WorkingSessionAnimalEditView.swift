//
//  WorkingSessionAnimalEditView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

struct WorkingSessionAnimalEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(\.modelContext) private var context

    let session: WorkingSession
    @Bindable var queueItem: WorkingQueueItem

    // SwiftData predicate macros can be unreliable when comparing relationship values.
    // Fetch broadly and filter in-memory for stable compilation and behavior.
    @Query(sort: [SortDescriptor(\WorkingTreatmentRecord.itemName)])
    private var allTreatmentRecords: [WorkingTreatmentRecord]

    @Query(sort: [SortDescriptor(\PregnancyCheck.date, order: .reverse)])
    private var allPregChecks: [PregnancyCheck]

    @Query(sort: [SortDescriptor(\HealthRecord.date, order: .reverse)])
    private var allHealthRecords: [HealthRecord]

    @Query(sort: \Pasture.name) private var pastures: [Pasture]

    private var animal: Animal? { queueItem.animal }

    // Treatments
    @State private var treatmentEntries: [TreatmentEditEntry] = []

    // Preg check
    @State private var recordPregCheck: Bool = false
    @State private var pregResult: PregnancyResult = .unknown
    @State private var pregDate: Date = .now
    @State private var estimatedDaysText: String = ""
    @State private var dueDate: Date = .now
    @State private var selectedSire: Animal?
    @State private var showingSirePicker: Bool = false

    // Castration / observations
    @State private var castrationPerformedInSession: Bool = false
    @State private var observationNotes: String = ""

    init(session: WorkingSession, queueItem: WorkingQueueItem) {
        self.session = session
        self._queueItem = Bindable(wrappedValue: queueItem)
    }

    private var sid: PersistentIdentifier { session.persistentModelID }
    private var aid: PersistentIdentifier? { queueItem.animal?.persistentModelID }

    private var treatmentRecords: [WorkingTreatmentRecord] {
        guard let aid else { return [] }
        return allTreatmentRecords.filter {
            $0.session?.persistentModelID == sid && $0.animal?.persistentModelID == aid
        }
    }

    private var pregChecks: [PregnancyCheck] {
        guard let aid else { return [] }
        return allPregChecks.filter {
            $0.workingSession?.persistentModelID == sid && $0.animal.persistentModelID == aid
        }
    }

    private var observationRecords: [HealthRecord] {
        guard let aid else { return [] }
        return allHealthRecords.filter {
            $0.workingSession?.persistentModelID == sid && $0.animal.persistentModelID == aid && $0.treatment == "Observation"
        }
    }

    private var castrationRecords: [HealthRecord] {
        guard let aid else { return [] }
        return allHealthRecords.filter {
            $0.workingSession?.persistentModelID == sid && $0.animal.persistentModelID == aid && $0.treatment == "Castration"
        }
    }

    private var isFemale: Bool {
        guard let animal else { return false }
        return animal.designation == .cow || animal.designation == .heifer
    }

    private var showPregSection: Bool {
        guard let animal else { return false }
        return isFemale && animal.ageInMonths >= WorkingConstants.pregCheckEligibleMonths
    }

    var body: some View {
        Form {
            Section {
                if let animal {
                    HStack {
                        let def = tagColorLibrary.resolvedDefinition(for: animal)
                        TagColorTagIcon(color: def.color, accessibilityLabel: "Tag color: \(def.name)")
                        Text(tagColorLibrary.formattedTag(for: animal))
                            .font(.title3.bold())
                        Spacer()
                        Text(animal.designation.rawValue.capitalized)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Missing animal")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Queue") {
                Picker("Status", selection: $queueItem.status) {
                    ForEach(WorkingQueueStatus.allCases, id: \.self) { s in
                        Text(s.rawValue.capitalized).tag(s)
                    }
                }

                if queueItem.status == .done {
                    DatePicker("Completed", selection: completedBinding, displayedComponents: [.date, .hourAndMinute])
                }

                if let source = queueItem.collectedFromPasture?.name ?? session.sourcePasture?.name {
                    LabeledContent("Collected from", value: source)
                }

                Picker("Destination", selection: $queueItem.destinationPasture) {
                    Text("None").tag(Optional<Pasture>(nil))
                    ForEach(pastures) { pasture in
                        Text(pasture.name).tag(Optional(pasture))
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
                            DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date])

                            Button {
                                showingSirePicker = true
                            } label: {
                                HStack {
                                    Text("Sire")
                                    Spacer()
                                    Text(selectedSire.map { tagColorLibrary.formattedTag(for: $0) } ?? "Choose")
                                        .foregroundStyle(selectedSire == nil ? .secondary : .primary)
                                }
                            }
                        }
                    }
                }
            }

            Section("Procedures") {
                Toggle("Castration performed (this session)", isOn: $castrationPerformedInSession)
                    .disabled(animal == nil)
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
                .disabled(animal == nil)
            } footer: {
                Text("Deletes treatments, preg checks, and session-tied records for this animal in this session. It does not delete movement or status history.")
            }
        }
        .navigationTitle("Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
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

    private var completedBinding: Binding<Date> {
        Binding<Date>(
            get: { queueItem.completedAt ?? session.date },
            set: { queueItem.completedAt = $0 }
        )
    }

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
        // Treatments: map existing records by item name
        let map = Dictionary(grouping: treatmentRecords, by: { $0.itemName })

        treatmentEntries = session.protocolItems.map { item in
            let existing = map[item.name]?.sorted(by: { $0.date > $1.date }).first
            let qtyText = {
                if let q = existing?.quantity { return "\(q)" }
                if let d = item.defaultQuantity { return "\(d)" }
                return ""
            }()
            return TreatmentEditEntry(
                id: item.id,
                name: item.name,
                given: existing?.given ?? true,
                quantityText: qtyText,
                date: existing?.date ?? session.date
            )
        }

        // Preg check
        if let existing = pregChecks.first {
            recordPregCheck = true
            pregResult = existing.result
            pregDate = existing.date
            estimatedDaysText = existing.estimatedDaysPregnant.map { "\($0)" } ?? ""
            dueDate = existing.dueDate ?? session.date
            selectedSire = existing.sireAnimal
        } else {
            recordPregCheck = false
            pregResult = .unknown
            pregDate = session.date
            estimatedDaysText = ""
            dueDate = session.date
            selectedSire = nil
        }

        // Session-tied castration/observation
        castrationPerformedInSession = !castrationRecords.isEmpty
        observationNotes = observationRecords.first?.notes ?? ""
    }

    private func recalcDueDate() {
        guard pregResult == .pregnant else { return }
        guard let est = Int(estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }

        let remaining = max(0, WorkingConstants.gestationDays - est)
        if let computed = Calendar.current.date(byAdding: .day, value: remaining, to: pregDate) {
            dueDate = computed
        }
    }

    private func save() {
        guard let animal else { return }

        let sid = session.persistentModelID
        let aid = animal.persistentModelID

        // Queue bookkeeping
        if queueItem.status == .done && queueItem.completedAt == nil {
            queueItem.completedAt = .now
        }
        if queueItem.status != .done {
            queueItem.completedAt = nil
        }

        // Upsert treatments
        if let existing = try? context.fetch(FetchDescriptor<WorkingTreatmentRecord>()) {
            for r in existing where r.session?.persistentModelID == sid && r.animal?.persistentModelID == aid {
                context.delete(r)
            }
        }
        for entry in treatmentEntries {
            let qty = Double(entry.quantityText.trimmingCharacters(in: .whitespacesAndNewlines))
            let rec = WorkingTreatmentRecord(
                date: entry.date,
                itemName: entry.name,
                given: entry.given,
                quantity: qty,
                animal: animal,
                session: session
            )
            context.insert(rec)
        }

        // Upsert preg checks for this session+animal
        if let existingChecks = try? context.fetch(FetchDescriptor<PregnancyCheck>()) {
            for c in existingChecks where c.workingSession?.persistentModelID == sid && c.animal.persistentModelID == aid {
                context.delete(c)
            }
        }

        if showPregSection && recordPregCheck {
            let estDays = Int(estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines))
            let computedDue: Date? = (pregResult == .pregnant) ? dueDate : nil

            if pregResult == .open || pregResult == .pregnant {
                let check = PregnancyCheck(
                    date: pregDate,
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

        // Upsert session-tied castration record
        if let existing = try? context.fetch(FetchDescriptor<HealthRecord>()) {
            for r in existing where r.workingSession?.persistentModelID == sid && r.animal.persistentModelID == aid && r.treatment == "Castration" {
                context.delete(r)
            }
        }
        if castrationPerformedInSession {
            let rec = HealthRecord(date: .now, treatment: "Castration", notes: nil, workingSession: session, animal: animal)
            context.insert(rec)
        }

        // Upsert session-tied observation record
        if let existing = try? context.fetch(FetchDescriptor<HealthRecord>()) {
            for r in existing where r.workingSession?.persistentModelID == sid && r.animal.persistentModelID == aid && r.treatment == "Observation" {
                context.delete(r)
            }
        }
        let trimmedObs = observationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedObs.isEmpty {
            let rec = HealthRecord(date: .now, treatment: "Observation", notes: trimmedObs, workingSession: session, animal: animal)
            context.insert(rec)
        }

        try? context.save()
        dismiss()
    }

    private func deleteWorkDataForAnimal() {
        guard let animal else { return }

        let sid = session.persistentModelID
        let aid = animal.persistentModelID

        if let treatments = try? context.fetch(FetchDescriptor<WorkingTreatmentRecord>()) {
            for r in treatments where r.session?.persistentModelID == sid && r.animal?.persistentModelID == aid {
                context.delete(r)
            }
        }
        if let checks = try? context.fetch(FetchDescriptor<PregnancyCheck>()) {
            for c in checks where c.workingSession?.persistentModelID == sid && c.animal.persistentModelID == aid {
                context.delete(c)
            }
        }
        if let health = try? context.fetch(FetchDescriptor<HealthRecord>()) {
            for h in health where h.workingSession?.persistentModelID == sid && h.animal.persistentModelID == aid {
                context.delete(h)
            }
        }

        queueItem.status = .queued
        queueItem.completedAt = nil
        try? context.save()

        seedState()
    }
}

private struct TreatmentEditEntry: Identifiable {
    let id: UUID
    var name: String
    var given: Bool
    var quantityText: String
    var date: Date
}
