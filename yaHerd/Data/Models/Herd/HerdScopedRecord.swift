//
//  HerdScopedRecord.swift
//  yaHerd
//

import SwiftData

protocol HerdScopedRecord: AnyObject {
    var herd: Herd? { get set }
}

extension Animal: HerdScopedRecord {}
extension AnimalTag: HerdScopedRecord {}
extension AnimalStatusReference: HerdScopedRecord {}
extension StatusRecord: HerdScopedRecord {}
extension HealthRecord: HerdScopedRecord {}
extension PregnancyCheck: HerdScopedRecord {}
extension MovementRecord: HerdScopedRecord {}
extension Pasture: HerdScopedRecord {}
extension PastureGroup: HerdScopedRecord {}
extension TagColorDefinition: HerdScopedRecord {}
extension WorkingSession: HerdScopedRecord {}
extension WorkingQueueItem: HerdScopedRecord {}
extension WorkingTreatmentRecord: HerdScopedRecord {}
extension WorkingProtocolTemplate: HerdScopedRecord {}
extension FieldCheckSession: HerdScopedRecord {}
extension FieldCheckAnimalCheck: HerdScopedRecord {}
extension FieldCheckFinding: HerdScopedRecord {}

extension ModelContext {
    func assignDefaultHerd<Record: HerdScopedRecord>(to record: Record) throws {
        guard record.herd == nil else { return }
        record.herd = try DefaultHerdBootstrapper.defaultHerd(in: self)
    }

    func insertIntoDefaultHerd<Record: PersistentModel & HerdScopedRecord>(_ record: Record) throws {
        try assignDefaultHerd(to: record)
        insert(record)
    }

    func insertIntoDefaultHerdIfAvailable<Record: PersistentModel & HerdScopedRecord>(_ record: Record) {
        try? assignDefaultHerd(to: record)
        insert(record)
    }
}
