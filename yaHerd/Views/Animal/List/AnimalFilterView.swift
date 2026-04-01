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
        case alive
        case sold
        case deceased

        init(status: AnimalStatus?) {
            switch status {
            case .alive:
                self = .alive
            case .sold:
                self = .sold
            case .deceased:
                self = .deceased
            case nil:
                self = .any
            }
        }

        var animalStatus: AnimalStatus? {
            switch self {
            case .any:
                return nil
            case .alive:
                return .alive
            case .sold:
                return .sold
            case .deceased:
                return .deceased
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Binding var filter: AnimalFilter
    @Binding var showArchived: Bool
    
    @Query private var pastures: [Pasture]

    private var statusSelection: Binding<StatusSelection> {
        Binding(
            get: {
                if !showArchived, filter.status == nil {
                    return .alive
                }

                return StatusSelection(status: filter.status)
            },
            set: { newValue in
                filter.status = newValue.animalStatus

                switch newValue {
                case .any:
                    showArchived = true
                case .alive:
                    if showArchived, filter.status == nil {
                        showArchived = false
                    }
                case .sold, .deceased:
                    showArchived = true
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Visibility") {
                    Toggle("Show Archived", isOn: $showArchived)
                }

                Section("Status") {
                    Picker("Status", selection: statusSelection) {
                        Text("Any").tag(StatusSelection.any)
                        Text("Alive").tag(StatusSelection.alive)
                        Text("Sold").tag(StatusSelection.sold)
                        Text("Deceased").tag(StatusSelection.deceased)
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
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        filter.clear()
                        showArchived = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
