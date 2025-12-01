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
    @Query(sort: \Animal.tagNumber) private var animals: [Animal]

    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(animals) { animal in
                    NavigationLink(value: animal) {
                        VStack(alignment: .leading) {
                            Text("Tag \(animal.tagNumber)")
                            Text(animal.sex.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Herd")
            .navigationDestination(for: Animal.self) { animal in
                AnimalDetailView(animal: animal)
            }
            .toolbar {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddAnimalView()
            }
        }
    }

    private func delete(offsets: IndexSet) {
        for index in offsets {
            context.delete(animals[index])
        }
    }
}
