//
//  AddAnimalView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//


import SwiftUI
import SwiftData

struct AddAnimalView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var tagNumber = ""
	@State private var tagColor: TagColor = .yellow
    @State private var biologicalSex: BiologicalSex = .female
    @State private var isCastrated: Bool = false
    @State private var birthDate = Date()
    @State private var status: AnimalStatus = .alive
    @State private var sire = ""
    @State private var dam = ""

    @State private var showingSirePicker = false
    @State private var showingDamPicker = false

    @State private var errorMessage: String?
    @State private var showingError = false

    private var computedDesignation: Sex {
        Animal.computeDesignation(
            biologicalSex: biologicalSex,
            isCastrated: isCastrated,
            birthDate: birthDate,
            referenceDate: Date()
        )
    }


    var body: some View {
        NavigationStack {
            Form {
                TextField("Tag Number", text: $tagNumber)
				Picker("Tag Color", selection: $tagColor) {
					ForEach(TagColor.allCases) { color in
						HStack(spacing: 10) {
							TagColorDot(tagColor: color)
							Text(color.label)
						}
						.tag(color)
					}
				}
                Picker("Biological Sex", selection: $biologicalSex) {
                    ForEach(BiologicalSex.allCases, id: \.self) { sex in
                        Text(sex.label).tag(sex)
                    }
                }
                .onChange(of: biologicalSex) { newValue in
                    if newValue != .male { isCastrated = false }
                }

                if biologicalSex == .male {
                    Toggle("Castrated", isOn: $isCastrated)
                }

                Text("Designation: \(computedDesignation.rawValue.capitalized)")
                    .foregroundStyle(.secondary)
                DatePicker("Birth Date", selection: $birthDate, displayedComponents: .date)
                Picker("Status", selection: $status) {
                    ForEach(AnimalStatus.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                }

                Section("Parents") {
                    HStack {
                        TextField("Sire", text: $sire)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Pick") { showingSirePicker = true }
                    }
                    if !sire.isEmpty {
                        Button("Clear Sire") { sire = "" }
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        TextField("Dam", text: $dam)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Pick") { showingDamPicker = true }
                    }
                    if !dam.isEmpty {
                        Button("Clear Dam") { dam = "" }
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Animal")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { validateAndSave() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
            }
            .alert("Validation Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .sheet(isPresented: $showingSirePicker) {
            AnimalParentPickerView(
                title: "Select Sire",
                excludeTagNumber: tagNumber,
                suggestedSexes: [.bull]
            ) { picked in
                sire = picked.tagNumber
            }
        }
        .sheet(isPresented: $showingDamPicker) {
            AnimalParentPickerView(
                title: "Select Dam",
                excludeTagNumber: tagNumber,
                suggestedSexes: [.cow, .heifer]
            ) { picked in
                dam = picked.tagNumber
            }
        }
    }

    private func validateAndSave() {
        do {
            try ValidationService.validateAnimal(
                tagNumber: tagNumber,
                birthDate: birthDate,
                context: context
            )

			let animal = Animal(
				tagNumber: tagNumber,
				tagColor: tagColor,
				sex: computedDesignation,
                birthDate: birthDate,
                status: status,
                sire: sire.isEmpty ? nil : sire,
                dam: dam.isEmpty ? nil : dam
            )

            context.insert(animal)
            dismiss()

        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
