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
    
    var body: some View {
        List {
            Section("Animal Info") {
                Text("Tag: \(animal.tagNumber)")
                Text("Sex: \(animal.sex.rawValue.capitalized)")
                Text("Status: \(animal.status.rawValue.capitalized)")
                Text("Birth Date: \(animal.birthDate.formatted(date: .long, time: .omitted))")
                Text("Status: \(animal.status.rawValue.capitalized)")
                    .foregroundStyle(animal.status == .alive ? .green : (animal.status == .sold ? .yellow : .red))
            }
            
            Section("Pasture") {
                if let pasture = animal.pasture {
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
                            Text(check.result.rawValue.capitalized)
                            Text(check.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
            PasturePickerView(animal: animal)
        }
        .sheet(isPresented: $showingAddHealth) {
            HealthRecordAddView(animal: animal)
        }
        .sheet(isPresented: $showingAddPregCheck) {
            PregnancyCheckAddView(animal: animal)
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
