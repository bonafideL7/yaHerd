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

    @Query(sort: [SortDescriptor(\WorkingTreatmentRecord.itemName)])
    private var allTreatmentRecords: [WorkingTreatmentRecord]

    @Query(sort: [SortDescriptor(\PregnancyCheck.date, order: .reverse)])
    private var allPregChecks: [PregnancyCheck]

    @Query(sort: [SortDescriptor(\HealthRecord.date, order: .reverse)])
    private var allHealthRecords: [HealthRecord]

    @Query(sort: \Pasture.name) private var pastures: [Pasture]

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

    init(session: WorkingSession, queueItem: WorkingQueueItem) {
        self.session = session
        self._queueItem = Bindable(wrappedValue: queueItem)
    }

    private var animal: Animal? { queueItem.animal }
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
            $0.workingSession?.persistentModelID == sid
                && $0.animal.persistentModelID == aid
                && $0.treatment == "Observation"
        }
    }

    private var castrationRecords: [HealthRecord] {
        guard let aid else { return [] }
        return allHealthRecords.filter {
            $0.workingSession?.persistentModelID == sid
                && $0.animal.persistentModelID == aid
                && $0.treatment == "Castration"
        }
    }

    private var isFemale: Bool {
        guard let animal else { return false }
        return (animal.sex ?? .female) == .female
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

            Section("Queue") {
                Picker("Status", selection: $queueItem.status) {
                    ForEach(WorkingQueueStatus.allCases, id: \.self) { status in
                        Text(status.rawValue.capitalized).tag(status)
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
        .alert("Can’t Save", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var completedBinding: Binding<Date> {
        Binding(
            get: { queueItem.completedAt ?? session.date },
            set: { queueItem.completedAt = $0 }
        )
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
        let map = Dictionary(grouping: treatmentRecords, by: { $0.itemName })

        treatmentEntries = session.protocolItems.map { item in
            let existing = map[item.name]?.sorted(by: { $0.date > $1.date }).first
            let qtyText: String = {
                if let quantity = existing?.quantity { return "\(quantity)" }
                if let defaultQuantity = item.defaultQuantity { return "\(defaultQuantity)" }
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

        if let existing = pregChecks.first {
            recordPregCheck = true
            pregResult = existing.result
            pregDate = existing.date
            estimatedDaysText = existing.estimatedDaysPregnant.map { "\($0)" } ?? ""
            dueDate = existing.dueDate ?? session.date
            selectedSire = existing.sireAnimal.map {
                AnimalParentOption(
                    id: $0.publicID,
                    displayTagNumber: $0.displayTagNumber,
                    displayTagColorID: $0.displayTagColorID,
                    sex: $0.sex ?? .female,
                    isArchived: $0.isArchived
                )
            }
        } else {
            recordPregCheck = false
            pregResult = .unknown
            pregDate = session.date
            estimatedDaysText = ""
            dueDate = session.date
            selectedSire = nil
        }

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

        if queueItem.status == .done && queueItem.completedAt == nil {
            queueItem.completedAt = .now
        }
        if queueItem.status != .done {
            queueItem.completedAt = nil
        }

        if let existing = try? context.fetch(FetchDescriptor<WorkingTreatmentRecord>()) {
            for record in existing where record.session?.persistentModelID == sid && record.animal?.persistentModelID == aid {
                context.delete(record)
            }
        }
        for entry in treatmentEntries {
            let quantity = Double(entry.quantityText.trimmingCharacters(in: .whitespacesAndNewlines))
            let record = WorkingTreatmentRecord(
                date: entry.date,
                itemName: entry.name,
                given: entry.given,
                quantity: quantity,
                animal: animal,
                session: session
            )
            context.insert(record)
        }

        if let existingChecks = try? context.fetch(FetchDescriptor<PregnancyCheck>()) {
            for check in existingChecks where check.workingSession?.persistentModelID == sid && check.animal.persistentModelID == aid {
                context.delete(check)
            }
        }

        if showPregSection && recordPregCheck {
            let estDays = Int(estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines))
            let computedDue: Date? = pregResult == .pregnant ? dueDate : nil

            if pregResult == .open || pregResult == .pregnant {
                let check = PregnancyCheck(
                    date: pregDate,
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

        if let existing = try? context.fetch(FetchDescriptor<HealthRecord>()) {
            for record in existing where record.workingSession?.persistentModelID == sid && record.animal.persistentModelID == aid && record.treatment == "Castration" {
                context.delete(record)
            }
        }
        if castrationPerformedInSession {
            let record = HealthRecord(date: .now, treatment: "Castration", notes: nil, workingSession: session, animal: animal)
            context.insert(record)
        }

        if let existing = try? context.fetch(FetchDescriptor<HealthRecord>()) {
            for record in existing where record.workingSession?.persistentModelID == sid && record.animal.persistentModelID == aid && record.treatment == "Observation" {
                context.delete(record)
            }
        }
        let trimmedObs = observationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedObs.isEmpty {
            let record = HealthRecord(date: .now, treatment: "Observation", notes: trimmedObs, workingSession: session, animal: animal)
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

    private func deleteWorkDataForAnimal() {
        guard let animal else { return }

        let sid = session.persistentModelID
        let aid = animal.persistentModelID

        if let treatments = try? context.fetch(FetchDescriptor<WorkingTreatmentRecord>()) {
            for record in treatments where record.session?.persistentModelID == sid && record.animal?.persistentModelID == aid {
                context.delete(record)
            }
        }
        if let checks = try? context.fetch(FetchDescriptor<PregnancyCheck>()) {
            for check in checks where check.workingSession?.persistentModelID == sid && check.animal.persistentModelID == aid {
                context.delete(check)
            }
        }
        if let health = try? context.fetch(FetchDescriptor<HealthRecord>()) {
            for record in health where record.workingSession?.persistentModelID == sid && record.animal.persistentModelID == aid {
                context.delete(record)
            }
        }

        queueItem.status = .queued
        queueItem.completedAt = nil

        do {
            try context.save()
            seedState()
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

private struct TreatmentEditEntry: Identifiable {
    let id: UUID
    var name: String
    var given: Bool
    var quantityText: String
    var date: Date
}
