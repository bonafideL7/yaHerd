//
//  AnimalFilter.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import Foundation

struct AnimalFilter {
    var biologicalSex: BiologicalSex? = nil
    var status: AnimalStatus? = nil
    var pasture: Pasture? = nil

    var isActive: Bool {
        biologicalSex != nil || status != nil || pasture != nil
    }

    mutating func clear() {
        biologicalSex = nil
        status = nil
        pasture = nil
    }
}
