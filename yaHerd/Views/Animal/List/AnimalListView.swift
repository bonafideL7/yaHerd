//
//  AnimalListView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI
import SwiftData

struct AnimalListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Query private var animals: [Animal]
    @AppStorage("allowHardDelete") private var allowHardDelete = false
    @State private var searchText = ""
    @State private var sortOrder: AnimalSortOrder = .tagAscending
    @State private var showingAdd = false
    @State private var showingFilters = false
    @State private var filter = AnimalFilter()
    @State private var showArchived = false

    @State private var batchMode = false
    @State private var selectedAnimals: Set<Animal> = []
    @State private var showingBatchMoveSheet = false

    var body: some View {
        Group {
            if batchMode {
                // SELECTION MODE — NO NAVIGATION
                List(selection: $selectedAnimals) {
                    ForEach(filteredAndSortedAnimals) { animal in
                        HStack(spacing: 12) {
                            let def = tagColorLibrary.resolvedDefinition(for: animal)
                            TagColorTagIcon(color: def.color, accessibilityLabel: "Tag color: \(def.name)")
                            Text(animal.tagNumber)

                            VStack(alignment: .leading) {
                                Text(animal.name)
                                    .font(.headline)
                                Text((animal.sex ?? .female).label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if animal.location == .workingPen {
                                    Text("Working Pen")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                } else if let pasture = animal.pasture {
                                    Text(pasture.name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tag(animal)
                    }
                    .onDelete(perform: deleteAnimals)
                }
                .environment(\.editMode, .constant(.active))
            } else {
                // NORMAL MODE — NAVIGATION ENABLED
                List {
                    ForEach(filteredAndSortedAnimals) { animal in
                        NavigationLink(value: animal) {
                            HStack(spacing: 12) {
                                let def = tagColorLibrary.resolvedDefinition(for: animal)
                                TagColorTagIcon(color: def.color, accessibilityLabel: "Tag color: \(def.name)")
                                Text(animal.tagNumber)

                                VStack(alignment: .leading) {
                                    Text(animal.name)
                                        .font(.headline)
                                    Text((animal.sex ?? .female).label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if animal.location == .workingPen {
                                        Text("Working Pen")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    } else if let pasture = animal.pasture {
                                        Text(pasture.name)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteAnimals)
                }
            }
        }
        .environment(\.editMode, .constant(batchMode ? .active : .inactive))
        .navigationTitle("Herd")
        .navigationDestination(for: Animal.self) { animal in
            AnimalDetailView(animal: animal)
        }
        .searchable(text: $searchText, prompt: "Search tag...")
        .toolbar {

            ToolbarItem(placement: .topBarLeading) {
                Button(batchMode ? "Done" : "Select") {
                    batchMode.toggle()
                    if !batchMode { selectedAnimals.removeAll() }
                }
            }

            ToolbarItem(placement: .bottomBar) {
                if batchMode && !selectedAnimals.isEmpty {
                    Button("Move to Pasture") {
                        showingBatchMoveSheet = true
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFilters = true
                } label: {
                    Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(AnimalSortOrder.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.icon)
                                .tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showArchived.toggle()
                } label: {
                    Image(systemName: showArchived ? "eye.slash" : "eye")
                }
            }

        }
        .sheet(isPresented: $showingAdd) {
            AddAnimalView()
        }
        .sheet(isPresented: $showingFilters) {
            AnimalFilterView(filter: $filter)
        }
        .sheet(isPresented: $showingBatchMoveSheet) {
            BatchMoveSheet(
                animals: Array(selectedAnimals),
                onComplete: {
                    selectedAnimals.removeAll()
                    batchMode = false
                }
            )
        }

    }

    private func deleteAnimals(at offsets: IndexSet) {
        for index in offsets {
            let animal = filteredAndSortedAnimals[index]

            if allowHardDelete {
                // Hard delete (permanent)
                context.delete(animal)
            } else {
                // Soft delete (archive)
                animal.status = .deceased
            }
        }

        try? context.save()
    }

    private var filteredAndSortedAnimals: [Animal] {
        var result = animals

        // HIDE SOLD + DECEASED unless user wants to see them
        if !showArchived {
            result = result.filter { $0.status == .alive }
        }

        // SEARCH
        if !searchText.isEmpty {
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            result = result.filter {
                $0.tagNumber.localizedCaseInsensitiveContains(q)
                || tagColorLibrary.formattedTag(for: $0).localizedCaseInsensitiveContains(q)
            }
        }

        // FILTER: Sex
        if let selectedSex = filter.sex {
            result = result.filter { $0.sex == selectedSex }
        }

        // FILTER: STATUS
        if let selectedStatus = filter.status {
            result = result.filter { $0.status == selectedStatus }
        }

        // FILTER: PASTURE
        if let selectedPasture = filter.pasture {
            result = result.filter { $0.pasture == selectedPasture }
        }

        // SORT
        switch sortOrder {
        case .tagAscending:
            result.sort { $0.tagNumber.localizedStandardCompare($1.tagNumber) == .orderedAscending }
        case .tagDescending:
            result.sort { $0.tagNumber.localizedStandardCompare($1.tagNumber) == .orderedDescending }
        case .birthDateNewest:
            result.sort { $0.birthDate > $1.birthDate }
        case .birthDateOldest:
            result.sort { $0.birthDate < $1.birthDate }
        case .sex:
            result.sort { ($0.sex?.rawValue ?? "") < ($1.sex?.rawValue ?? "") }
        case .status:
            result.sort { $0.status.rawValue < $1.status.rawValue }
        }

        return result
    }
}

