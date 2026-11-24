//
//  PastureTilePickerView.swift
//  yaHerd
//
//  Created by mm on 12/8/25.
//

import SwiftUI

struct PastureTilePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pastureFeatureDependencies) private var pastureDependencies
    private var pastureListRepository: any PastureListReader { pastureDependencies.listRepository }
    @Environment(ApplicationSettings.self) private var applicationSettings
    @Environment(AppCurrentHerdSelection.self) private var herdSelection

    /// Called when user selects a pasture
    let onSelect: (PastureSummary) -> Void

    @State private var model = PastureTilePickerViewModel()
    @State private var loadedHerdID: UUID?
    @State private var loadedSelectionRevision: UInt64?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isShowingCurrentHerdPastures {
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
                    } else if herdSelection.currentHerdID == nil {
                        ContentUnavailableView(
                            "Select a Herd",
                            systemImage: "square.stack.3d.up"
                        )
                    } else {
                        ProgressView("Loading Pastures")
                    }
                }
                .padding(.top)
            }
            .navigationTitle("Choose Pasture")
            .task(id: herdSelection.selectionRevision) {
                loadPastures()
            }
            .onChange(of: pastureDependencies.mutationStream.pastureRevision) { _, _ in
                guard isShowingCurrentHerdPastures else { return }
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

    private var isShowingCurrentHerdPastures: Bool {
        guard let herdID = herdSelection.currentHerdID else { return false }
        return loadedHerdID == herdID &&
            loadedSelectionRevision == herdSelection.selectionRevision
    }

    private func loadPastures() {
        loadedHerdID = nil
        loadedSelectionRevision = nil
        model.reset()
        guard let herdID = herdSelection.currentHerdID else { return }
        // A device-wide legacy recent name has no trustworthy Herd owner.
        // Never map its name onto a different Herd's pasture.
        _ = model.load(
            using: pastureListRepository,
            recentPastureIDs: applicationSettings.recentPastureIDs(for: herdID),
            legacyRecentPastureNames: []
        )
        loadedHerdID = herdID
        loadedSelectionRevision = herdSelection.selectionRevision
    }

    private func selectPasture(_ pasture: PastureSummary) {
        guard let herdID = loadedHerdID,
              herdSelection.currentHerdID == herdID,
              loadedSelectionRevision == herdSelection.selectionRevision else { return }
        applicationSettings.setRecentPastureIDs(model.select(pasture), for: herdID)
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
