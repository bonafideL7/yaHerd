//
//  AnimalListInlineEntryDialogs.swift
//

import SwiftUI

struct AnimalListInlineEntryDialogs: ViewModifier {
    @Binding var sex: Sex
    @Binding var pastureID: UUID?
    @Binding var birthDate: Date
    @Binding var isShowingSexPicker: Bool
    @Binding var isShowingPasturePicker: Bool
    @Binding var isShowingBirthDateOptions: Bool
    @Binding var isShowingBirthDatePicker: Bool

    let pastureOptions: [PastureOption]
    let calendar: Calendar
    let dateProvider: any DateProviding
    let onPrepareBirthDatePicker: () -> Void
    let onRequestFocus: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Sex", isPresented: $isShowingSexPicker, titleVisibility: .visible) {
                sexOptions
            }
            .confirmationDialog("Pasture", isPresented: $isShowingPasturePicker, titleVisibility: .visible) {
                pastureOptionsContent
            }
            .confirmationDialog("Birthdate", isPresented: $isShowingBirthDateOptions, titleVisibility: .visible) {
                birthDateOptions
            }
            .sheet(isPresented: $isShowingBirthDatePicker) {
                AnimalListInlineEntryDatePickerSheet(
                    birthDate: $birthDate,
                    onDone: closeBirthDatePicker,
                    onDismiss: onRequestFocus
                )
            }
    }

    @ViewBuilder
    private var sexOptions: some View {
        ForEach(Sex.allCases, id: \.self) { option in
            Button(option.label) {
                sex = option
                onRequestFocus()
            }
        }
    }

    @ViewBuilder
    private var pastureOptionsContent: some View {
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

    @ViewBuilder
    private var birthDateOptions: some View {
        Button("Today") {
            birthDate = today
            onRequestFocus()
        }

        Button("Yesterday") {
            birthDate = yesterday
            onRequestFocus()
        }

        Button("Choose Date…") {
            onPrepareBirthDatePicker()
            isShowingBirthDatePicker = true
        }
    }

    private var today: Date {
        calendar.startOfDay(for: dateProvider.now)
    }

    private var yesterday: Date {
        calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    private func closeBirthDatePicker() {
        isShowingBirthDatePicker = false
        onRequestFocus()
    }
}

extension View {
    func animalListInlineEntryDialogs(
        sex: Binding<Sex>,
        pastureID: Binding<UUID?>,
        birthDate: Binding<Date>,
        isShowingSexPicker: Binding<Bool>,
        isShowingPasturePicker: Binding<Bool>,
        isShowingBirthDateOptions: Binding<Bool>,
        isShowingBirthDatePicker: Binding<Bool>,
        pastureOptions: [PastureOption],
        calendar: Calendar = .current,
        dateProvider: any DateProviding = SystemDateProvider(),
        onPrepareBirthDatePicker: @escaping () -> Void,
        onRequestFocus: @escaping () -> Void
    ) -> some View {
        modifier(
            AnimalListInlineEntryDialogs(
                sex: sex,
                pastureID: pastureID,
                birthDate: birthDate,
                isShowingSexPicker: isShowingSexPicker,
                isShowingPasturePicker: isShowingPasturePicker,
                isShowingBirthDateOptions: isShowingBirthDateOptions,
                isShowingBirthDatePicker: isShowingBirthDatePicker,
                pastureOptions: pastureOptions,
                calendar: calendar,
                dateProvider: dateProvider,
                onPrepareBirthDatePicker: onPrepareBirthDatePicker,
                onRequestFocus: onRequestFocus
            )
        )
    }
}
