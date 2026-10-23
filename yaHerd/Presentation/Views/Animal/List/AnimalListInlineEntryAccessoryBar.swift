//
//  AnimalListInlineEntryAccessoryBar.swift
//

import SwiftUI

// The existing quick-entry attributes live with the active animal row,
// rather than occupying a separate bottom safe-area accessory.
struct AnimalListInlineEntryAccessoryBar: View {
    @Binding var text: String
    @Binding var sex: Sex
    @Binding var birthDate: Date
    @Binding var pastureID: UUID?
    let pastureOptions: [PastureOption]
    let isEditing: Bool
    let parentSummary: String
    let onToggleParents: () -> Void
    let onPreparePicker: () -> Void
    let onShowBirthDatePicker: () -> Void
    let onRequestFocus: () -> Void
    let onSubmit: () -> Void

    @State private var isShowingSexOptions = false
    @State private var isShowingPastureOptions = false
    @State private var isShowingBirthDateOptions = false

    private let calendar = Calendar.current
    private let dateProvider: any DateProviding = SystemDateProvider()

    var body: some View {
        HStack(spacing: 8) {
            accessoryButton(
                systemName: "figure.stand",
                accessibilityLabel: "Sex",
                accessibilityValue: sex.label,
                action: {
                    onPreparePicker()
                    isShowingSexOptions = true
                }
            )
            .confirmationDialog("Sex", isPresented: $isShowingSexOptions, titleVisibility: .visible) {
                ForEach(Sex.allCases, id: \.self) { option in
                    Button(option.label) {
                        sex = option
                        onRequestFocus()
                    }
                }
            }

            accessoryButton(
                systemName: "leaf",
                accessibilityLabel: "Pasture",
                accessibilityValue: selectedPastureLabel,
                action: {
                    onPreparePicker()
                    isShowingPastureOptions = true
                }
            )
            .confirmationDialog("Pasture", isPresented: $isShowingPastureOptions, titleVisibility: .visible) {
                Button("No Pasture") {
                    pastureID = nil
                    onRequestFocus()
                }

                ForEach(pastureOptions) { pasture in
                    Button(pasture.name) {
                        pastureID = pasture.id
                        onRequestFocus()
                    }
                }
            }

            accessoryButton(
                systemName: "calendar",
                accessibilityLabel: "Birthdate",
                accessibilityValue: birthDate.formatted(date: .abbreviated, time: .omitted),
                action: {
                    onPreparePicker()
                    isShowingBirthDateOptions = true
                }
            )
            .confirmationDialog("Birthdate", isPresented: $isShowingBirthDateOptions, titleVisibility: .visible) {
                Button("Today") {
                    birthDate = calendar.startOfDay(for: dateProvider.now)
                    onRequestFocus()
                }

                Button("Yesterday") {
                    let today = calendar.startOfDay(for: dateProvider.now)
                    birthDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
                    onRequestFocus()
                }

                Button("Choose Date…", action: onShowBirthDatePicker)
            }

            accessoryButton(
                systemName: "person.2",
                accessibilityLabel: "Parents",
                accessibilityValue: parentSummary,
                action: onToggleParents
            )

            Spacer(minLength: 8)

            Button(action: onSubmit) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .background(.thinMaterial, in: Circle())
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(isEditing ? "Save animal" : "Add animal")
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity)
    }

    private var selectedPastureLabel: String {
        guard let pastureID else { return "No Pasture" }
        return pastureOptions.first(where: { $0.id == pastureID })?.name ?? "Pasture"
    }

    private func accessoryButton(
        systemName: String,
        accessibilityLabel: String,
        accessibilityValue: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.thinMaterial, in: Circle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }
}
