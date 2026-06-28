//
//  AnimalParentPickerSheetModifier.swift
//

import SwiftUI

private struct AnimalParentPickerSheetModifier: ViewModifier {
    @Binding var activePicker: ParentPickerType?
    @Binding var sireID: UUID?
    @Binding var sire: String
    @Binding var damID: UUID?
    @Binding var dam: String

    let excludeAnimalID: UUID?

    func body(content: Content) -> some View {
        content.sheet(item: $activePicker) { picker in
            switch picker {
            case .sire:
                AnimalParentPickerView(
                    title: "Select Sire",
                    excludeAnimalID: excludeAnimalID,
                    suggestedSexes: [.male]
                ) { picked in
                    sireID = picked.id
                    sire = picked.displayName
                    activePicker = nil
                }
            case .dam:
                AnimalParentPickerView(
                    title: "Select Dam",
                    excludeAnimalID: excludeAnimalID,
                    suggestedSexes: [.female]
                ) { picked in
                    damID = picked.id
                    dam = picked.displayName
                    activePicker = nil
                }
            }
        }
    }
}

extension View {
    func animalParentPickerSheet(
        activePicker: Binding<ParentPickerType?>,
        sireID: Binding<UUID?>,
        sire: Binding<String>,
        damID: Binding<UUID?>,
        dam: Binding<String>,
        excludeAnimalID: UUID?
    ) -> some View {
        modifier(
            AnimalParentPickerSheetModifier(
                activePicker: activePicker,
                sireID: sireID,
                sire: sire,
                damID: damID,
                dam: dam,
                excludeAnimalID: excludeAnimalID
            )
        )
    }
}
