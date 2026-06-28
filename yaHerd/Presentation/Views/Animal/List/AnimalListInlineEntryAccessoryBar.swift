//
//  AnimalListInlineEntryAccessoryBar.swift
//

import SwiftUI

struct AnimalListInlineEntryAccessoryBar: View {
    @Binding var text: String
    @Binding var sex: Sex
    @Binding var birthDate: Date
    @Binding var pastureID: UUID?
    let pastureOptions: [PastureOption]
    let isEditing: Bool
    let onShowSexPicker: () -> Void
    let onShowPasturePicker: () -> Void
    let onShowBirthDateOptions: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            accessoryButton(
                systemName: "figure.stand",
                accessibilityLabel: "Sex",
                accessibilityValue: sex.label,
                action: onShowSexPicker
            )

            accessoryButton(
                systemName: "leaf",
                accessibilityLabel: "Pasture",
                accessibilityValue: selectedPastureLabel,
                action: onShowPasturePicker
            )

            accessoryButton(
                systemName: "calendar",
                accessibilityLabel: "Birthdate",
                accessibilityValue: birthDate.formatted(date: .abbreviated, time: .omitted),
                action: onShowBirthDateOptions
            )

            Spacer(minLength: 12)

            Button(action: onSubmit) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(isEditing ? "Save animal" : "Add animal")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar, in: Capsule())
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
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }
}
