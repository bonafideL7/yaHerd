//
//  Pasture.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//


import SwiftData
import Foundation

@Model
final class Pasture {
    @Attribute(.unique) var name: String
    var acreage: Double?

    @Relationship(deleteRule: .nullify, inverse: \Animal.pasture)
    var animals: [Animal] = []

    init(name: String, acreage: Double? = nil) {
        self.name = name
        self.acreage = acreage
    }
}
