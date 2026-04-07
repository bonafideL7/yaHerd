//
//  AddPastureGroupView.swift
//  yaHerd
//
//  Created by mm on 12/14/25.
//


import SwiftUI
import SwiftData

struct AddPastureGroupView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var grazeDays = 7
    @State private var restDays = 21

    var body: some View {
        NavigationStack {
            Form {
                TextField("Group Name", text: $name)
                
                Stepper("Graze Days: \(grazeDays)", value: $grazeDays, in: 1...30)
                Stepper("Rest Days: \(restDays)", value: $restDays, in: 7...90)
            }
            .navigationTitle("New Pasture Group")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(
                            PastureGroup(
                                name: name,
                                grazeDays: grazeDays,
                                restDays: restDays
                            )
                        )
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
