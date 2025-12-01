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
    @State var animal: Animal

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
}
