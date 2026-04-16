//
//  AnimalFilterView.swift
//

import SwiftUI

struct AnimalFilterView: View {
    private enum StatusSelection: Hashable {
        case any
        case active
        case sold
        case dead

        init(status: AnimalStatus?) {
            switch status {
            case .active:
                self = .active
            case .sold:
                self = .sold
            case .dead:
                self = .dead
            case nil:
                self = .any
            }
        }

        var animalStatus: AnimalStatus? {
            switch self {
            case .any:
                return nil
            case .active:
                return .active
            case .sold:
                return .sold
            case .dead:
                return .dead
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    @Binding var filter: AnimalFilter
    @Binding var showRemovedStatuses: Bool
    @Binding var showArchivedRecords: Bool

    let pastureOptions: [PastureOption]

    private var statusSelection: Binding<StatusSelection> {
        Binding(
            get: {
                if !showRemovedStatuses, filter.status == nil {
                    return .active
                }
                return StatusSelection(status: filter.status)
            },
            set: { newValue in
                switch newValue {
                case .any:
                    filter.status = nil
                    showRemovedStatuses = true
                case .active:
                    filter.status = nil
                    showRemovedStatuses = false
                case .sold, .dead:
                    filter.status = newValue.animalStatus
                    showRemovedStatuses = true
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Visibility") {
                    Toggle("Include off-herd animals", isOn: $showRemovedStatuses)
                    Toggle("Show archived records", isOn: $showArchivedRecords)
                }

                Section("Status") {
                    Picker("Status", selection: statusSelection) {
                        Text("Any").tag(StatusSelection.any)
                        Text("Active").tag(StatusSelection.active)
                        Text("Sold").tag(StatusSelection.sold)
                        Text("Dead").tag(StatusSelection.dead)
                    }
                }

                Section("Sex") {
                    Picker("Sex", selection: Binding(
                        get: { filter.sex },
                        set: { filter.sex = $0 }
                    )) {
                        Text("Any").tag(Sex?.none)

                        ForEach(Sex.allCases, id: \.self) { sex in
                            Text(sex.label)
                                .tag(Sex?.some(sex))
                        }
                    }
                }

                Section("Animal Type") {
                    Picker("Animal Type", selection: Binding(
                        get: { filter.animalType },
                        set: { filter.animalType = $0 }
                    )) {
                        Text("Any").tag(AnimalType?.none)

                        ForEach(AnimalType.allCases, id: \.self) { animalType in
                            Text(animalType.label)
                                .tag(AnimalType?.some(animalType))
                        }
                    }
                }

                Section("Pasture") {
                    Picker("Pasture", selection: Binding(
                        get: { filter.pastureID },
                        set: { filter.pastureID = $0 }
                    )) {
                        Text("Any").tag(UUID?.none)

                        ForEach(pastureOptions) { pasture in
                            Text(pasture.name)
                                .tag(UUID?.some(pasture.id))
                        }
                    }
                }
            }
            .onChange(of: showRemovedStatuses) { _, newValue in
                if !newValue {
                    filter.status = nil
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        filter.clear()
                        showRemovedStatuses = false
                        showArchivedRecords = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
