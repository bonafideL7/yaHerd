//
//  PastureGroup.swift
//  yaHerd
//
//  Created by mm on 12/14/25.
//


import SwiftData
import Foundation

@Model
final class PastureGroup {
    @Attribute(.unique) var name: String
    
    var grazeDays: Int
    var restDays: Int

    @Relationship(
        deleteRule: .nullify,
        inverse: \Pasture.group
    )
    var pastures: [Pasture] = []

    init(name: String, grazeDays: Int = 7, restDays: Int = 21) {
        self.name = name
        self.grazeDays = grazeDays
        self.restDays = restDays
    }
}
