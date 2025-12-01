//
//  AnimalListFilteredView.swift
//  yaHerd
//
//  Created by mm on 11/29/25.
//


import SwiftUI

struct AnimalListFilteredView: View {
    var title: String
    var animals: [Animal]

    var body: some View {
        List {
            ForEach(animals) { animal in
                NavigationLink(value: animal) {
                    Text("Tag \(animal.tagNumber)")
                }
            }
        }
        .navigationTitle(title)
    }
}
