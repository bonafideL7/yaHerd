//
//  AnimalFilterView.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import SwiftUI
import SwiftData

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
    @Binding var showSoftDeletedRecords: Bool

    @Query private var pastures: [Pasture]

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
                    Toggle("Show soft-deleted records", isOn: $showSoftDeletedRecords)
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

                Section("Pasture") {
                    Picker("Pasture", selection: Binding(
                        get: { filter.pasture },
                        set: { filter.pasture = $0 }
                    )) {
                        Text("Any").tag(Pasture?.none)

                        ForEach(pastures) { pasture in
                            Text(pasture.name)
                                .tag(Pasture?.some(pasture))
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
                        showSoftDeletedRecords = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
