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
        List(selection: $selectedAnimals) {
            ForEach(filteredAndSortedAnimals) { animal in
                NavigationLink(value: animal) {
                    VStack(alignment: .leading) {
                        Text("Tag \(animal.tagNumber)")
                            .font(.headline)

                        Text(animal.sex.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteAnimals)
        }
        .environment(\.editMode, .constant(batchMode ? .active : .inactive))
        .navigationTitle("Herd")
        .navigationDestination(for: Animal.self) { animal in
            AnimalDetailView(animal: animal)
        }
        .searchable(text: $searchText, prompt: "Search tag...")
        .toolbar {
            
            // ENTER / EXIT BATCH MODE
            ToolbarItem(placement: .topBarLeading) {
                Button(batchMode ? "Done" : "Select") {
                    batchMode.toggle()
                    if !batchMode { selectedAnimals.removeAll() }
                }
            }

            // MOVE TO PASTURE (only visible in batch mode + some selected)
            ToolbarItem(placement: .bottomBar) {
                if batchMode && !selectedAnimals.isEmpty {
                    Button("Move to Pasture") {
                        showingBatchMoveSheet = true
                    }
                }
            }

            // ADD BUTTON
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            // FILTER BUTTON
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFilters = true
                } label: {
                    Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }

            // SORT MENU
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
            result = result.filter { $0.tagNumber.localizedCaseInsensitiveContains(searchText) }
        }

        // FILTER: SEX
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
            result.sort { $0.sex.rawValue < $1.sex.rawValue }
        case .status:
            result.sort { $0.status.rawValue < $1.status.rawValue }
        }

        return result
    }
}

