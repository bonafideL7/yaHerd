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
    var name: String = ""
    
    var grazeDays: Int = 7
    var restDays: Int = 21

    @Relationship(
        deleteRule: .nullify,
        inverse: \Pasture.group
    )
    var pastureStorage: [Pasture]?

    var pastures: [Pasture] {
        get { pastureStorage ?? [] }
        set { pastureStorage = newValue }
    }

    init(name: String, grazeDays: Int = 7, restDays: Int = 21) {
        self.name = name
        self.grazeDays = grazeDays
        self.restDays = restDays
    }
}
