//
//  AnimalListInlineEntryDatePickerSheet.swift
//

import SwiftUI

struct AnimalListInlineEntryDatePickerSheet: View {
    @Binding var birthDate: Date
    let onDone: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Birthdate",
                    selection: $birthDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
            }
            .navigationTitle("Birthdate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarDoneButton(action: onDone)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear(perform: onDismiss)
    }
}
