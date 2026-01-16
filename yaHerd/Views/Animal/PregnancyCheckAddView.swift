//
//  PregnancyCheckAddView.swift
//  yaHerd
//
//  Created by mm on 11/29/25.
//


import SwiftUI
import SwiftData

struct PregnancyCheckAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State var animal: Animal

    @State private var date = Date()
    @State private var result: PregnancyResult = .unknown
    @State private var technician = ""
    @State private var estimatedDaysText: String = ""
    @State private var dueDate: Date = .now
    @State private var selectedSire: Animal?
    @State private var showingSirePicker = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Check Date", selection: $date, displayedComponents: .date)

                Picker("Result", selection: $result) {
                    ForEach(PregnancyResult.allCases, id: \.self) { value in
                        Text(value.rawValue.capitalized)
                    }
                }

                TextField("Technician", text: $technician)

                if result == .pregnant {
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
                            Text(selectedSire?.tagNumber ?? "Choose")
                                .foregroundStyle(selectedSire == nil ? .secondary : .primary)
                        }
                    }
                }
            }
            .navigationTitle("Add Pregnancy Check")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Validation Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onChange(of: estimatedDaysText) { _, _ in
            recalcDueDate()
        }
        .sheet(isPresented: $showingSirePicker) {
            AnimalParentPickerView(
                title: "Select Sire",
                excludeAnimal: animal,
                suggestedSexes: [.bull]
            ) { picked in
                selectedSire = picked
            }
        }
    }

    private func save() {
        do {
            try ValidationService.validatePregCheck()

            let check = PregnancyCheck(
                date: date,
                result: result,
                technician: technician.isEmpty ? nil : technician,
                estimatedDaysPregnant: Int(estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)),
                dueDate: result == .pregnant ? dueDate : nil,
                sireAnimal: selectedSire,
                workingSession: nil,
                animal: animal
            )

            context.insert(check)
            dismiss()

        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func recalcDueDate() {
        guard result == .pregnant else { return }
        guard let est = Int(estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let remaining = max(0, WorkingConstants.gestationDays - est)
        if let computed = Calendar.current.date(byAdding: .day, value: remaining, to: date) {
            dueDate = computed
        }
    }

}
