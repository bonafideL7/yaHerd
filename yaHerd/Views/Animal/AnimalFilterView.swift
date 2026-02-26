//
//  AnimalFilterView.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import SwiftUI
import SwiftData

struct AnimalFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Binding var filter: AnimalFilter

    @Query private var pastures: [Pasture]

    var body: some View {
        NavigationStack {
            Form {

                Section("Biological Sex") {
                    Picker("Biological Sex", selection: Binding(
                        get: { filter.biologicalSex },
                        set: { filter.biologicalSex = $0 }
                    )) {
                        Text("Any").tag(BiologicalSex?.none)

                        ForEach(BiologicalSex.allCases, id: \.self) { sex in
                            Text(sex.label)
                                .tag(BiologicalSex?.some(sex))
                        }
                    }
                }

                Section("Status") {
                    Picker("Status", selection: Binding(
                        get: { filter.status },
                        set: { filter.status = $0 }
                    )) {
                        Text("Any").tag(AnimalStatus?.none)

                        ForEach(AnimalStatus.allCases, id: \.self) { s in
                            Text(s.rawValue.capitalized)
                                .tag(AnimalStatus?.some(s))
                        }
                    }
                }

                Section("Pasture") {
                    Picker("Pasture", selection: Binding(
                        get: { filter.pasture },
                        set: { filter.pasture = $0 }
                    )) {
                        Text("Any").tag(Pasture?.none)

                        ForEach(pastures) { pasture in
                            Text(pasture.name)
                                .tag(Pasture?.some(pasture))
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        filter.clear()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
