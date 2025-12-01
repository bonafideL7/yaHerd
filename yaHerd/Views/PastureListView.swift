//
//  PastureListView.swift
//  yaHerd
//
//  Created by mm on 11/29/25.
//


import SwiftUI
import SwiftData

struct PastureListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Pasture.name) private var pastures: [Pasture]

    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(pastures) { pasture in
                    NavigationLink(value: pasture) {
                        VStack(alignment: .leading) {
                            Text(pasture.name)
                            if let acreage = pasture.acreage {
                                Text("\(acreage.formatted()) acres")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Pastures")
            .navigationDestination(for: Pasture.self) { pasture in
                PastureDetailView(pasture: pasture)
            }
            .toolbar {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddPastureView()
            }
        }
    }

    private func delete(offsets: IndexSet) {
        for index in offsets {
            context.delete(pastures[index])
        }
    }
}
