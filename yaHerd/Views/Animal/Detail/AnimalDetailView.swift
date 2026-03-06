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
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @AppStorage("allowHardDelete") private var allowHardDelete = false
    var animal: Animal
    @State private var showingPasturePicker = false
    @State private var showingAddHealth = false
    @State private var showingAddPregCheck = false
    @State private var showingSirePicker = false
    @State private var showingDamPicker = false

    private var tagColorIDBinding: Binding<UUID> {
        Binding(
            get: { animal.tagColorID ?? tagColorLibrary.defaultColor.id },
            set: { newValue in
                animal.tagColorID = newValue
                try? context.save()
            }
        )
    }
    private var sexBinding: Binding<Sex> {
        Binding(
            get: { animal.sex ?? .female },
            set: { newValue in
                animal.sex = newValue
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
                    Text("Name")
                    Spacer()
                    Text(animal.name)
                }
                
                HStack {
                    Text("Tag")
                    Spacer()
                    HStack(spacing: 8) {
                        let def = tagColorLibrary.resolvedDefinition(for: animal)
                        TagColorTagIcon(color: def.color, accessibilityLabel: "Tag color: \(def.name)")
                        Text(tagColorLibrary.formattedTag(for: animal))
                    }
                }

                Picker("Tag Color", selection: tagColorIDBinding) {
                    ForEach(tagColorLibrary.colors) { def in
                        HStack(spacing: 10) {
                            TagColorTagIcon(color: def.color, accessibilityLabel: "Tag color: \(def.name)")
                            Text("\(def.name) (\(def.prefix))")
                        }
                        .tag(def.id)
                    }
                }
                Picker("Sex", selection: sexBinding) {
                    ForEach(Sex.allCases, id: \.self) { sex in
                        Text(sex.label).tag(sex)
                    }
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

//            Section("Pregnancy Checks") {
//                if animal.pregnancyChecks.isEmpty {
//                    Text("No records")
//                } else {
//                    ForEach(animal.pregnancyChecks) { check in
//                        VStack(alignment: .leading) {
//                            let title: String = {
//                                var t = check.result.rawValue.capitalized
//                                if check.result == .pregnant, let due = check.dueDate {
//                                    t += " (Due \(due.formatted(date: .abbreviated, time: .omitted)))"
//                                }
//                                return t
//                            }()
//                            Text(title)
//                            Text(check.date.formatted(date: .abbreviated, time: .omitted))
//                                .font(.caption)
//                                .foregroundStyle(.secondary)
//                            if let sire = check.sireAnimal?.tagNumber {
//                                Text("Sire: \(sire)")
//                                    .font(.caption)
//                                    .foregroundStyle(.secondary)
//                            }
//                        }
//                    }
//                }
//            }

//            Section("Health Records") {
//                if animal.healthRecords.isEmpty {
//                    Text("No records")
//                } else {
//                    ForEach(animal.healthRecords.sorted(by: { $0.date > $1.date })) { record in
//                        VStack(alignment: .leading) {
//                            Text(record.treatment)
//                            Text(record.date.formatted(date: .abbreviated, time: .omitted))
//                                .font(.caption)
//                                .foregroundStyle(.secondary)
//                        }
//                    }
//                }
//            }

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
        .navigationTitle("Animal \(tagColorLibrary.formattedTag(for: animal))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
//                Button("Add Preg Check") {
//                    showingAddPregCheck = true
//                }
//
//                Button("Add Health") {
//                    showingAddHealth = true
//                }

//                Button("Change Pasture") {
//                            showingPasturePicker = true
//                        }
            }

//            ToolbarItem(placement: .topBarTrailing) {
//                NavigationLink {
//                    AnimalTimelineView(animal: animal)
//                } label: {
//                    Image(systemName: "clock.arrow.circlepath")
//                }
//            }
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
//        .sheet(isPresented: $showingAddHealth) {
//            HealthRecordAddView(animal: animal)
//        }
//        .sheet(isPresented: $showingAddPregCheck) {
//            PregnancyCheckAddView(animal: animal)
//        }

        .sheet(isPresented: $showingSirePicker) {
            AnimalParentPickerView(
                title: "Select Sire",
                excludeAnimal: animal,
                suggestedSexes: [.male]
            ) { picked in
                animal.sire = picked.tagNumber
                try? context.save()
            }
        }
        .sheet(isPresented: $showingDamPicker) {
            AnimalParentPickerView(
                title: "Select Dam",
                excludeAnimal: animal,
                suggestedSexes: [.female]
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
