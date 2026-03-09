//
//  AnimalDetailView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI
import SwiftData

struct AnimalDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @AppStorage("allowHardDelete") private var allowHardDelete = false

    var animal: Animal

    @Query(sort: \Pasture.name) private var pastures: [Pasture]

    private var nameBinding: Binding<String> {
        Binding(
            get: { animal.name },
            set: { newValue in
                animal.name = newValue
                try? context.save()
            }
        )
    }

    private var tagNumberBinding: Binding<String> {
        Binding(
            get: { animal.tagNumber },
            set: { newValue in
                animal.tagNumber = newValue
                try? context.save()
            }
        )
    }

    private var tagColorIDBinding: Binding<UUID?> {
        Binding(
            get: { animal.tagColorID },
            set: { newValue in
                animal.tagColorID = newValue
                try? context.save()
            }
        )
    }

    private var sexBinding: Binding<Sex> {
        Binding(
            get: { animal.sex ?? .female },
            set: { newValue in
                animal.sex = newValue
                try? context.save()
            }
        )
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { animal.birthDate },
            set: { newValue in
                animal.birthDate = newValue
                try? context.save()
            }
        )
    }

    private var statusBinding: Binding<AnimalStatus> {
        Binding(
            get: { animal.status },
            set: { newValue in
                guard animal.status != newValue else { return }
                let oldStatus = animal.status
                animal.status = newValue

                let record = StatusRecord(
                    date: Date(),
                    oldStatus: oldStatus,
                    newStatus: newValue,
                    animal: animal
                )
                context.insert(record)
                try? context.save()
            }
        )
    }

    private var pastureBinding: Binding<Pasture?> {
        Binding(
            get: { animal.pasture },
            set: { newValue in
                updatePasture(to: newValue)
            }
        )
    }

    private var sireBinding: Binding<String> {
        Binding(
            get: { animal.sire ?? "" },
            set: { newValue in
                animal.sire = newValue.isEmpty ? nil : newValue
                try? context.save()
            }
        )
    }

    private var damBinding: Binding<String> {
        Binding(
            get: { animal.dam ?? "" },
            set: { newValue in
                animal.dam = newValue.isEmpty ? nil : newValue
                try? context.save()
            }
        )
    }

    var body: some View {
        Form {
            AnimalFormView(
                name: nameBinding,
                tagNumber: tagNumberBinding,
                tagColorID: tagColorIDBinding,
                sex: sexBinding,
                birthDate: birthDateBinding,
                status: statusBinding,
                pasture: pastureBinding,
                sire: sireBinding,
                dam: damBinding,
                pastures: pastures,
                excludeAnimal: animal
            )

            Section("Status Actions") {
                if animal.status != .sold {
                    Button("Mark as Sold") {
                        updateStatus(.sold)
                    }
                }

                if animal.status != .deceased {
                    Button("Mark as Deceased") {
                        updateStatus(.deceased)
                    }
                }

                if animal.status != .alive {
                    Button("Restore to Alive") {
                        updateStatus(.alive)
                    }
                    .foregroundStyle(.blue)
                }
            }

            Section("Delete Animal") {
                Button("Archive (Soft Delete)") {
                    updateStatus(.deceased)
                }
                .foregroundStyle(.orange)

                if allowHardDelete {
                    Button("Permanently Delete", role: .destructive) {
                        context.delete(animal)
                        try? context.save()
                    }
                }
            }
        }
        .navigationTitle("Animal \(tagColorLibrary.formattedTag(for: animal))")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func updatePasture(to newPasture: Pasture?) {
        let oldName = animal.pasture?.name
        let newName = newPasture?.name

        guard oldName != newName else { return }

        animal.pasture = newPasture
        animal.location = .pasture
        animal.activeWorkingSession = nil

        let movement = MovementRecord(
            date: .now,
            fromPasture: oldName,
            toPasture: newName,
            animal: animal
        )
        context.insert(movement)

        try? context.save()
    }

    private func updateStatus(_ newStatus: AnimalStatus) {
        let oldStatus = animal.status
        animal.status = newStatus

        let record = StatusRecord(
            date: Date(),
            oldStatus: oldStatus,
            newStatus: newStatus,
            animal: animal
        )
        context.insert(record)

        try? context.save()
    }
}
