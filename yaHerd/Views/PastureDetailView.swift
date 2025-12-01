//
//  PastureDetailView.swift
//  yaHerd
//
//  Created by mm on 11/29/25.
//


import SwiftUI
import SwiftData

struct PastureDetailView: View {
    @Environment(\.modelContext) private var context
    @State var pasture: Pasture

    var body: some View {
        List {
            Section("Pasture Info") {
                Text("Name: \(pasture.name)")
                if let acres = pasture.acreage {
                    Text("Acreage: \(acres.formatted())")
                }
            }

            Section("Animals in Pasture") {
                if pasture.animals.isEmpty {
                    Text("No animals assigned")
                } else {
                    ForEach(pasture.animals.sorted(by: { $0.tagNumber < $1.tagNumber })) { animal in
                        NavigationLink(value: animal) {
                            VStack(alignment: .leading) {
                                Text("Tag \(animal.tagNumber)")
                                Text(animal.sex.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(pasture.name)
        .navigationDestination(for: Animal.self) { animal in
            AnimalDetailView(animal: animal)
        }
    }
}
