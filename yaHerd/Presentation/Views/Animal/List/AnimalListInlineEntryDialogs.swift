//
//  AnimalListInlineEntryDialogs.swift
//

import SwiftUI

// The quick-choice confirmation dialogs are anchored to their accessory buttons.
// Only the full birthdate picker remains presented from the owning animal list.
struct AnimalListInlineEntryDialogs: ViewModifier {
    @Binding var birthDate: Date
    @Binding var isShowingBirthDatePicker: Bool

    let onRequestFocus: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isShowingBirthDatePicker) {
                AnimalListInlineEntryDatePickerSheet(
                    birthDate: $birthDate,
                    onDone: closeBirthDatePicker,
                    onDismiss: onRequestFocus
                )
            }
    }

    private func closeBirthDatePicker() {
        isShowingBirthDatePicker = false
        onRequestFocus()
    }
}

extension View {
    func animalListInlineEntryDialogs(
        birthDate: Binding<Date>,
        isShowingBirthDatePicker: Binding<Bool>,
        onRequestFocus: @escaping () -> Void
    ) -> some View {
        modifier(
            AnimalListInlineEntryDialogs(
                birthDate: birthDate,
                isShowingBirthDatePicker: isShowingBirthDatePicker,
                onRequestFocus: onRequestFocus
            )
        )
    }
}
