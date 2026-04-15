//
//  PastureTilePickerView.swift
//  yaHerd
//
//  Created by mm on 12/8/25.
//


import SwiftUI

struct PastureTilePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies

    /// Called when user selects a pasture
    let onSelect: (PastureSummary) -> Void

    /// Raw storage for recent pasture names (pipe-delimited)
    @AppStorage("recentPastureNames") private var recentPastureNamesRaw: String = ""

    @State private var pastures: [PastureSummary] = []

    // Parsed recent names from storage
    private var recentNames: [String] {
        recentPastureNamesRaw.split(separator: "|").map(String.init)
    }

    private var recentPastures: [PastureSummary] {
        let nameSet = Set(recentNames)
        return pastures.filter { nameSet.contains($0.name) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

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
            .task { load() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func load() {
        do {
            pastures = try dependencies.pastureRepository.fetchPastures()
        } catch {
            pastures = []
        }
    }

    private func selectPasture(_ pasture: PastureSummary) {
        let name = pasture.name

        var names = recentNames
        names.removeAll(where: { $0 == name })
        names.insert(name, at: 0)
        if names.count > 4 {
            names = Array(names.prefix(4))
        }

        recentPastureNamesRaw = names.joined(separator: "|")

        onSelect(pasture)
        dismiss()
    }
}
