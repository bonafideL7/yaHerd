//
//  PastureTilePickerView.swift
//  yaHerd
//
//  Created by mm on 12/8/25.
//


import SwiftUI
import SwiftData
import LucideIcons

struct PastureTilePickerView: View {
    @Environment(\.dismiss) private var dismiss

    /// Called when user selects a pasture
    let onSelect: (Pasture) -> Void

    /// Raw storage for recent pasture names (pipe-delimited)
    @AppStorage("recentPastureNames") private var recentPastureNamesRaw: String = ""

    @Query(sort: \Pasture.name) private var pastures: [Pasture]

    // Parsed recent names from storage
    private var recentNames: [String] {
        recentPastureNamesRaw.split(separator: "|").map(String.init)
    }

    private var recentPastures: [Pasture] {
        let nameSet = Set(recentNames)
        return pastures.filter { nameSet.contains($0.name) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // QUICK ACTIONS
                    if !recentPastures.isEmpty {
                        Text("Recent")
                            .font(.title3.bold())
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(recentPastures) { pasture in
                                    QuickPastureCard(pasture: pasture) {
                                        selectPasture(pasture)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // ALL PASTURES GRID
                    Text("All Pastures")
                        .font(.title3.bold())
                        .padding(.horizontal)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 20) {
                        ForEach(pastures) { pasture in
                            PastureTileCard(pasture: pasture) {
                                selectPasture(pasture)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top)
            }
            .navigationTitle("Choose Pasture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Selection + recents
    private func selectPasture(_ pasture: Pasture) {
        let name = pasture.name

        var names = recentNames
        names.removeAll(where: { $0 == name })
        names.insert(name, at: 0)
        if names.count > 4 {
            names = Array(names.prefix(4))
        }

        // Write back to AppStorage
        recentPastureNamesRaw = names.joined(separator: "|")

        onSelect(pasture)
        dismiss()
    }
}

