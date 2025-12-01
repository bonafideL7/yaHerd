//
//  DashboardView.swift
//  yaHerd
//
//  Created by mm on 11/29/25.
//


import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query(sort: \Pasture.name) private var pastures: [Pasture]
    @Query private var animals: [Animal]

    var body: some View {
        NavigationStack {
            List {
                Section("Pasture Summary") {
                    // Animals with no pasture
                    let unassigned = animals.filter { $0.pasture == nil }
                    NavigationLink("No Pasture: \(unassigned.count)") {
                        AnimalListFilteredView(title: "Unassigned Animals", animals: unassigned)
                    }

                    // Animals grouped by pasture
                    ForEach(pastures) { pasture in
                        let count = pasture.animals.count

                        NavigationLink("\(pasture.name): \(count)") {
                            AnimalListFilteredView(
                                title: pasture.name,
                                animals: pasture.animals.sorted(by: { $0.tagNumber < $1.tagNumber })
                            )
                        }
                    }
                }
            }
            .navigationTitle("Dashboard")
        }
    }
}
