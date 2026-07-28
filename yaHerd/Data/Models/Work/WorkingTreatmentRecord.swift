//
//  WorkingTreatmentRecord.swift
//  yaHerd
//

import SwiftData
import Foundation

/// Stores per-animal treatment completion for a working session.
extension YaHerdSchemaV1 {
    @Model
    final class WorkingTreatmentRecord {
        var publicID: UUID = UUID()
        @Relationship(deleteRule: .nullify) var herd: Herd?
        var date: Date = Date.now

        /// Stable identifier of the planned treatment item. Names remain editable
        /// display snapshots and are not used to join records to the treatment plan.
        var treatmentItemID: UUID = UUID()
        var itemName: String = ""
        var given: Bool = false
        var doseAmount: Double?
        var doseUnit: WorkingTreatmentDoseUnit?
        var administrationRoute: WorkingTreatmentAdministrationRoute?

        @Relationship(deleteRule: .nullify)
        var animal: Animal?

        @Relationship(deleteRule: .nullify)
        var session: WorkingSession?

        var dose: WorkingTreatmentDose {
            get {
                WorkingTreatmentDose(
                    amount: doseAmount,
                    unit: doseUnit,
                    route: administrationRoute
                )
            }
            set {
                doseAmount = newValue.amount
                doseUnit = newValue.unit
                administrationRoute = newValue.route
            }
        }

        /// Transitional V1 source compatibility. New code uses `dose`.
        var quantity: Double? {
            get { doseAmount }
            set { doseAmount = newValue }
        }

        init(
            publicID: UUID = UUID(),
            date: Date = Date.now,
            treatmentItemID: UUID,
            itemName: String,
            given: Bool,
            dose: WorkingTreatmentDose = WorkingTreatmentDose(),
            animal: Animal,
            session: WorkingSession
        ) {
            self.publicID = publicID
            self.date = date
            self.treatmentItemID = treatmentItemID
            self.itemName = itemName
            self.given = given
            self.doseAmount = dose.amount
            self.doseUnit = dose.unit
            self.administrationRoute = dose.route
            self.animal = animal
            self.session = session
        }

        /// Transitional V1 source compatibility. The stable identity and route/unit
        /// are recovered from the session treatment plan when older callers provide
        /// only the treatment name and amount.
        convenience init(
            publicID: UUID = UUID(),
            date: Date = Date.now,
            itemName: String,
            given: Bool,
            quantity: Double? = nil,
            animal: Animal,
            session: WorkingSession
        ) {
            let plannedTreatment = session.protocolItems.first { $0.name == itemName }
            self.init(
                publicID: publicID,
                date: date,
                treatmentItemID: plannedTreatment?.id ?? UUID(),
                itemName: itemName,
                given: given,
                dose: WorkingTreatmentDose(
                    amount: quantity,
                    unit: plannedTreatment?.suggestedDose.unit,
                    route: plannedTreatment?.suggestedDose.route
                ),
                animal: animal,
                session: session
            )
        }
    }
}
