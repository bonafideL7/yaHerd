//
//  SyncDiagnosticsRepository.swift
//  yaHerd
//

import Foundation

struct SyncDiagnosticsStorageInfo: Equatable, Sendable {
    let technologyName: String
    let cloudKitContainerIdentifier: String
    let storeName: String
    let recoveryStoreName: String
}

struct SyncDiagnosticsAnimalIdentity: Equatable, Sendable {
    let summary: AnimalSummary
    let tagNumbers: Set<String>
}

struct SyncDiagnosticsPublicIDRecord: Equatable, Sendable {
    let entityType: PublicIDRepairEntityType
    let animal: SyncDiagnosticsAnimalIdentity?
    let date: Date?
    let fromPasture: String?
    let toPasture: String?
    let resultRawValue: String?
    let estimatedDaysPregnant: Int?
    let dueDate: Date?
    let technician: String?
    let oldStatusRawValue: String?
    let newStatusRawValue: String?

    init(
        entityType: PublicIDRepairEntityType,
        animal: SyncDiagnosticsAnimalIdentity? = nil,
        date: Date? = nil,
        fromPasture: String? = nil,
        toPasture: String? = nil,
        resultRawValue: String? = nil,
        estimatedDaysPregnant: Int? = nil,
        dueDate: Date? = nil,
        technician: String? = nil,
        oldStatusRawValue: String? = nil,
        newStatusRawValue: String? = nil
    ) {
        self.entityType = entityType
        self.animal = animal
        self.date = date
        self.fromPasture = fromPasture
        self.toPasture = toPasture
        self.resultRawValue = resultRawValue
        self.estimatedDaysPregnant = estimatedDaysPregnant
        self.dueDate = dueDate
        self.technician = technician
        self.oldStatusRawValue = oldStatusRawValue
        self.newStatusRawValue = newStatusRawValue
    }
}

@MainActor
protocol SyncDiagnosticsRepository: AnyObject {
    var publicIDRepairService: (any PublicIDRepairService)? { get }
    var storageInfo: SyncDiagnosticsStorageInfo? { get }

    func fetchCounts() throws -> SyncDiagnosticsCounts
    func fetchAnimalIdentity(publicID: UUID) throws -> SyncDiagnosticsAnimalIdentity?
    func fetchUniqueAnimalIdentity(tagNumber: String) throws -> SyncDiagnosticsAnimalIdentity?
    func fetchPublicIDRecord(
        entityType: PublicIDRepairEntityType,
        publicID: UUID
    ) throws -> SyncDiagnosticsPublicIDRecord?
}

extension SyncDiagnosticsRepository {
    var publicIDRepairService: (any PublicIDRepairService)? { nil }
    var storageInfo: SyncDiagnosticsStorageInfo? { nil }

    func fetchAnimalIdentity(publicID: UUID) throws -> SyncDiagnosticsAnimalIdentity? { nil }
    func fetchUniqueAnimalIdentity(tagNumber: String) throws -> SyncDiagnosticsAnimalIdentity? { nil }
    func fetchPublicIDRecord(
        entityType: PublicIDRepairEntityType,
        publicID: UUID
    ) throws -> SyncDiagnosticsPublicIDRecord? { nil }
}
