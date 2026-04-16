//
//  AnimalFilter.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//

import Foundation

struct AnimalFilter {
    var sex: Sex? = nil
    var animalType: AnimalType? = nil
    var status: AnimalStatus? = nil
    var pastureID: UUID? = nil

    var isActive: Bool {
        sex != nil || animalType != nil || status != nil || pastureID != nil
    }

    mutating func clear() {
        sex = nil
        animalType = nil
        status = nil
        pastureID = nil
    }
}
