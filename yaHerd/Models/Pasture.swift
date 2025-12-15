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
    @Relationship(deleteRule: .nullify, inverse: \Animal.pasture)
    var animals: [Animal] = []
    var acreage: Double?
    var usableAcreage: Double?
    var targetHeadPerAcre: Double?
    var lastGrazedDate: Date?
    var group: PastureGroup?

    init(name: String, acreage: Double? = nil, usableAcreage: Double? = nil, targetHeadPerAcre: Double? = nil) {
        self.name = name
        self.acreage = acreage
        self.usableAcreage = usableAcreage
        self.targetHeadPerAcre = targetHeadPerAcre
    }
}
