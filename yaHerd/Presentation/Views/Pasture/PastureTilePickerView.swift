//
//  PastureTilePickerView.swift
//  yaHerd
//
//  Created by mm on 12/8/25.
//

import SwiftUI

struct PastureTilePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pastureListRepository) private var pastureListRepository

    /// Called when user selects a pasture
    let onSelect: (PastureSummary) -> Void

    /// Raw storage for recent pasture IDs (pipe-delimited UUID strings)
    @AppStorage("recentPastureIDs") private var recentPastureIDsRaw = ""

    /// Legacy name-based storage kept only to migrate existing installs to ID-based storage.
    @AppStorage("recentPastureNames") private var legacyRecentPastureNamesRaw = ""

    @State private var model = PastureTilePickerViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !model.recentPastures.isEmpty {
                        pastureSection(
                            title: "Recent",
                            pastures: model.recentPastures,
                            layout: .horizontal
                        )
                    }

                    pastureSection(
                        title: "All Pastures",
                        pastures: model.pastures,
                        layout: .grid
                    )
                }
                .padding(.top)
            }
            .navigationTitle("Choose Pasture")
            .task {
                loadPastures()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                }
            }
            .alert("Can’t Load Pastures", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "Unknown error")
            }
        }
    }

    @ViewBuilder
    private func pastureSection(
        title: String,
        pastures: [PastureSummary],
        layout: PasturePickerSectionLayout
    ) -> some View {
        Text(title)
            .font(.title3.bold())
            .padding(.horizontal)

        switch layout {
        case .horizontal:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(pastures) { pasture in
                        QuickPastureCard(pasture: pasture) {
                            selectPasture(pasture)
                        }
                    }
                }
                .padding(.horizontal)
            }
        case .grid:
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
    }

    private func loadPastures() {
        if let migratedRawValue = model.load(
            using: pastureListRepository,
            recentPastureIDsRaw: recentPastureIDsRaw,
            legacyRecentPastureNamesRaw: legacyRecentPastureNamesRaw
        ) {
            recentPastureIDsRaw = migratedRawValue
            legacyRecentPastureNamesRaw = ""
        }
    }

    private func selectPasture(_ pasture: PastureSummary) {
        recentPastureIDsRaw = model.select(pasture)
        onSelect(pasture)
        dismiss()
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.errorMessage = nil
                }
            }
        )
    }
}

private enum PasturePickerSectionLayout {
    case horizontal
    case grid
}
