//
//  SwiftDataModel.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//
import SwiftData
import Foundation

@Model
final class Animal {
    @Attribute(.unique) var tagNumber: String
    var sex: Sex
    var birthDate: Date
    var status: AnimalStatus
    var sire: String?
    var dam: String?

    @Relationship(deleteRule: .cascade) var healthRecords: [HealthRecord] = []
    @Relationship(deleteRule: .cascade) var pregnancyChecks: [PregnancyCheck] = []
    @Relationship(deleteRule: .cascade) var movementRecords: [MovementRecord] = []
    @Relationship(deleteRule: .cascade) var statusRecords: [StatusRecord] = []

    @Relationship var pasture: Pasture?

    init(
        tagNumber: String,
        sex: Sex,
        birthDate: Date,
        status: AnimalStatus = .alive,
        sire: String? = nil,
        dam: String? = nil,
        pasture: Pasture? = nil
    ) {
        self.tagNumber = tagNumber
        self.sex = sex
        self.birthDate = birthDate
        self.status = status
        self.sire = sire
        self.dam = dam
        self.pasture = pasture
    }
}

enum Sex: String, Codable, CaseIterable {
    case cow
    case bull
    case heifer
    case steer
}

enum AnimalStatus: String, Codable, CaseIterable {
    case alive
    case sold
    case deceased
}
