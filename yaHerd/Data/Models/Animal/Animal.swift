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
    var publicID: UUID = UUID()
    var name: String = ""
    var tagNumber: String = ""
    var tagColorID: UUID?
    var sex: Sex?
    var birthDate: Date = Date.now
    var status: AnimalStatus = AnimalStatus.active
    var saleDate: Date?
    var salePrice: Double?
    var reasonSold: String?
    var deathDate: Date?
    var causeOfDeath: String?
    var statusReferenceID: UUID?
    var isSoftDeleted: Bool = false
    var softDeletedAt: Date?
    var softDeleteReason: String?
    var locationRaw: AnimalLocation? = AnimalLocation.pasture
    var distinguishingFeatures: [DistinguishingFeature] = []

    @Relationship(deleteRule: .cascade, inverse: \HealthRecord.animal) var healthRecordStorage: [HealthRecord]?
    @Relationship(deleteRule: .cascade, inverse: \PregnancyCheck.animal) var pregnancyCheckStorage: [PregnancyCheck]?
    @Relationship(deleteRule: .cascade, inverse: \MovementRecord.animal) var movementRecordStorage: [MovementRecord]?
    @Relationship(deleteRule: .cascade, inverse: \StatusRecord.animal) var statusRecordStorage: [StatusRecord]?
    @Relationship(deleteRule: .nullify) var activeWorkingSession: WorkingSession?
    @Relationship(deleteRule: .nullify) var sireAnimal: Animal?
    @Relationship(deleteRule: .nullify) var damAnimal: Animal?
    @Relationship(deleteRule: .nullify, inverse: \Animal.damAnimal) var maternalOffspringStorage: [Animal]?
    @Relationship(deleteRule: .nullify) var pasture: Pasture?
    @Relationship(deleteRule: .cascade, inverse: \AnimalTag.animal) var tagStorage: [AnimalTag]?
    @Relationship(deleteRule: .nullify, inverse: \Animal.sireAnimal) var paternalOffspringStorage: [Animal]?
    @Relationship(deleteRule: .nullify, inverse: \WorkingQueueItem.animal) var workingQueueItemStorage: [WorkingQueueItem]?
    @Relationship(deleteRule: .nullify, inverse: \WorkingTreatmentRecord.animal) var workingTreatmentRecordStorage: [WorkingTreatmentRecord]?
    @Relationship(deleteRule: .nullify, inverse: \FieldCheckAnimalCheck.animal) var fieldCheckAnimalCheckStorage: [FieldCheckAnimalCheck]?
    @Relationship(deleteRule: .nullify, inverse: \FieldCheckFinding.animal) var fieldCheckFindingStorage: [FieldCheckFinding]?
    @Relationship(deleteRule: .nullify, inverse: \PregnancyCheck.sireAnimal) var siredPregnancyCheckStorage: [PregnancyCheck]?

    var healthRecords: [HealthRecord] {
        get { healthRecordStorage ?? [] }
        set { healthRecordStorage = newValue }
    }

    var pregnancyChecks: [PregnancyCheck] {
        get { pregnancyCheckStorage ?? [] }
        set { pregnancyCheckStorage = newValue }
    }

    var movementRecords: [MovementRecord] {
        get { movementRecordStorage ?? [] }
        set { movementRecordStorage = newValue }
    }

    var statusRecords: [StatusRecord] {
        get { statusRecordStorage ?? [] }
        set { statusRecordStorage = newValue }
    }

    var maternalOffspring: [Animal] {
        get { maternalOffspringStorage ?? [] }
        set { maternalOffspringStorage = newValue }
    }

    var tags: [AnimalTag] {
        get { tagStorage ?? [] }
        set { tagStorage = newValue }
    }

    var location: AnimalLocation {
        get { locationRaw ?? .pasture }
        set { locationRaw = newValue }
    }

    var isActiveInHerd: Bool {
        status == .active && !isSoftDeleted
    }

    var isVisibleRecord: Bool {
        !isSoftDeleted
    }

    var isArchived: Bool {
        isSoftDeleted
    }

    var archivedAt: Date? {
        softDeletedAt
    }

    var archiveReason: String? {
        softDeleteReason
    }

    init(
        publicID: UUID = UUID(),
        name: String,
        tagNumber: String,
        tagColorID: UUID? = nil,
        birthDate: Date,
        status: AnimalStatus = AnimalStatus.active,
        saleDate: Date? = nil,
        salePrice: Double? = nil,
        reasonSold: String? = nil,
        deathDate: Date? = nil,
        causeOfDeath: String? = nil,
        statusReferenceID: UUID? = nil,
        isSoftDeleted: Bool = false,
        softDeletedAt: Date? = nil,
        softDeleteReason: String? = nil,
        sireAnimal: Animal? = nil,
        damAnimal: Animal? = nil,
        pasture: Pasture? = nil,
        sex: Sex? = nil,
        distinguishingFeatures: [DistinguishingFeature] = []
    ) {
        self.publicID = publicID
        self.name = name
        self.tagNumber = tagNumber
        self.tagColorID = tagColorID
        self.birthDate = birthDate
        self.status = status
        self.saleDate = saleDate
        self.salePrice = salePrice
        self.reasonSold = reasonSold
        self.deathDate = deathDate
        self.causeOfDeath = causeOfDeath
        self.statusReferenceID = statusReferenceID
        self.isSoftDeleted = isSoftDeleted
        self.softDeletedAt = softDeletedAt
        self.softDeleteReason = softDeleteReason
        self.sireAnimal = sireAnimal
        self.damAnimal = damAnimal
        self.pasture = pasture
        self.location = AnimalLocation.pasture
        self.activeWorkingSession = nil
        self.sex = sex ?? .unknown
        self.distinguishingFeatures = distinguishingFeatures
    }
}
