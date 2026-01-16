//
//  AnimalDetailView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI
import SwiftData

struct AnimalDetailView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("allowHardDelete") private var allowHardDelete = false
    var animal: Animal
    @State private var showingPasturePicker = false
    @State private var showingAddHealth = false
    @State private var showingAddPregCheck = false
    @State private var showingSirePicker = false
    @State private var showingDamPicker = false

    private var tagColorBinding: Binding<TagColor> {
        Binding(
            get: { animal.tagColor ?? .yellow },
            set: { newValue in
                animal.tagColor = newValue
                try? context.save()
            }
        )
    }
    private var biologicalSexBinding: Binding<BiologicalSex> {
        Binding(
            get: { animal.biologicalSex ?? animal.sex.inferredBiologicalSex },
            set: { newValue in
                animal.biologicalSex = newValue
                animal.syncLegacySexFromData()
                try? context.save()
            }
        )
    }

    private var isCastratedBinding: Binding<Bool> {
        Binding(
            get: { animal.isCastrated },
            set: { newValue in
                animal.isCastrated = newValue
                animal.syncLegacySexFromData()
                try? context.save()
            }
        )
    }



    private var sireBinding: Binding<String> {
        Binding(
            get: { animal.sire ?? "" },
            set: { newValue in
                animal.sire = newValue.isEmpty ? nil : newValue
                try? context.save()
            }
        )
    }

    private var damBinding: Binding<String> {
        Binding(
            get: { animal.dam ?? "" },
            set: { newValue in
                animal.dam = newValue.isEmpty ? nil : newValue
                try? context.save()
            }
        )
    }
    
    var body: some View {
        List {
            Section("Animal Info") {
                HStack {
                    Text("Tag")
                    Spacer()
                    HStack(spacing: 8) {
                        TagColorDot(tagColor: animal.tagColor ?? .yellow)
                        Text(animal.tagNumber)
                    }
                }

                Picker("Tag Color", selection: tagColorBinding) {
                    ForEach(TagColor.allCases) { color in
                        HStack(spacing: 10) {
                            TagColorDot(tagColor: color)
                            Text(color.label)
                        }
                        .tag(color)
                    }
                }
                Text("Designation: \(animal.designation.rawValue.capitalized)")
                Picker("Biological Sex", selection: biologicalSexBinding) {
                    ForEach(BiologicalSex.allCases, id: \.self) { sex in
                        Text(sex.label).tag(sex)
                    }
                }

                if (animal.biologicalSex ?? animal.sex.inferredBiologicalSex) == .male {
                    Toggle("Castrated", isOn: isCastratedBinding)
                }
                Text("Birth Date: \(animal.birthDate.formatted(date: .long, time: .omitted))")
                Text("Status: \(animal.status.rawValue.capitalized)")
                    .foregroundStyle(animal.status == .alive ? .green : (animal.status == .sold ? .yellow : .red))
            }

            Section("Parents") {
                HStack {
                    TextField("Sire", text: sireBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Pick") { showingSirePicker = true }
                }
                if !(animal.sire ?? "").isEmpty {
                    Button("Clear Sire") {
                        animal.sire = nil
                        try? context.save()
                    }
                    .foregroundStyle(.secondary)
                }

                HStack {
                    TextField("Dam", text: damBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Pick") { showingDamPicker = true }
                }
                if !(animal.dam ?? "").isEmpty {
                    Button("Clear Dam") {
                        animal.dam = nil
                        try? context.save()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            
            Section("Pasture") {
                if animal.location == .workingPen {
                    HStack {
                        Text("Working Pen")
                        Spacer()
                        Text(animal.activeWorkingSession?.protocolName ?? "")
                            .foregroundStyle(.secondary)
                    }
                } else if let pasture = animal.pasture {
                    Text(pasture.name)
                } else {
                    Text("None")
                }
            }
            
            Section("Pregnancy Checks") {
                if animal.pregnancyChecks.isEmpty {
                    Text("No records")
                } else {
                    ForEach(animal.pregnancyChecks) { check in
                        VStack(alignment: .leading) {
                            let title: String = {
                                var t = check.result.rawValue.capitalized
                                if check.result == .pregnant, let due = check.dueDate {
                                    t += " (Due \(due.formatted(date: .abbreviated, time: .omitted)))"
                                }
                                return t
                            }()
                            Text(title)
                            Text(check.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let sire = check.sireAnimal?.tagNumber {
                                Text("Sire: \(sire)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            
            Section("Health Records") {
                if animal.healthRecords.isEmpty {
                    Text("No records")
                } else {
                    ForEach(animal.healthRecords.sorted(by: { $0.date > $1.date })) { record in
                        VStack(alignment: .leading) {
                            Text(record.treatment)
                            Text(record.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Section("Status Actions") {
                if animal.status != .sold {
                    Button("Mark as Sold") {
                        updateStatus(.sold)
                    }
                }
                
                if animal.status != .deceased {
                    Button("Mark as Deceased") {
                        updateStatus(.deceased)
                    }
                }
                
                if animal.status != .alive {
                    Button("Restore to Alive") {
                        updateStatus(.alive)
                    }
                    .foregroundStyle(.blue)
                }
            }
            
            Section("Delete Animal") {
                // Soft delete always available
                Button("Archive (Soft Delete)") {
                    updateStatus(.deceased)   // ← Use your existing status-change function
                }
                .foregroundStyle(.orange)

                // Hard delete only if user explicitly enabled it
                if allowHardDelete {
                    Button("Permanently Delete", role: .destructive) {
                        context.delete(animal)
                        try? context.save()
                    }
                }
            }
            
        }
        .navigationTitle("Animal \(animal.tagNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Add Preg Check") {
                    showingAddPregCheck = true
                }
                
                Button("Add Health") {
                    showingAddHealth = true
                }
                
                Button("Change Pasture") {
                            showingPasturePicker = true
                        } 
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AnimalTimelineView(animal: animal)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
        .sheet(isPresented: $showingPasturePicker) {
            PastureTilePickerView { pasture in
                let oldName = animal.pasture?.name
                animal.pasture = pasture
                animal.location = .pasture
                animal.activeWorkingSession = nil
                animal.location = .pasture
                animal.activeWorkingSession = nil

                let record = MovementRecord(
                    date: .now,
                    fromPasture: oldName,
                    toPasture: pasture.name,
                    animal: animal
                )
                context.insert(record)

                try? context.save()
            }
        }
        .sheet(isPresented: $showingAddHealth) {
            HealthRecordAddView(animal: animal)
        }
        .sheet(isPresented: $showingAddPregCheck) {
            PregnancyCheckAddView(animal: animal)
        }

        .sheet(isPresented: $showingSirePicker) {
            AnimalParentPickerView(
                title: "Select Sire",
                excludeAnimal: animal,
                suggestedSexes: [.bull]
            ) { picked in
                animal.sire = picked.tagNumber
                try? context.save()
            }
        }
        .sheet(isPresented: $showingDamPicker) {
            AnimalParentPickerView(
                title: "Select Dam",
                excludeAnimal: animal,
                suggestedSexes: [.cow, .heifer]
            ) { picked in
                animal.dam = picked.tagNumber
                try? context.save()
            }
        }
        
    }
    
    private func updateStatus(_ newStatus: AnimalStatus) {
        let oldStatus = animal.status
        animal.status = newStatus

        // RECORD STATUS CHANGE
        let record = StatusRecord(
            date: Date(),
            oldStatus: oldStatus,
            newStatus: newStatus,
            animal: animal
        )
        context.insert(record)

        try? context.save()
    }
}
