import Foundation

enum DashboardMapper {
    static func makeAnimalRecord(from animal: Animal) -> DashboardAnimalRecord {
        let latestPregnancyCheck = animal.pregnancyChecks.max { lhs, rhs in
            lhs.date < rhs.date
        }
        let latestHealthRecord = animal.healthRecords.max { lhs, rhs in
            lhs.date < rhs.date
        }

        let expectedCalvingDate: Date? = {
            guard let latestPregnancyCheck else { return nil }
            if let dueDate = latestPregnancyCheck.dueDate {
                return dueDate
            }
            return Calendar.current.date(byAdding: .day, value: 283, to: latestPregnancyCheck.date)
        }()

        return DashboardAnimalRecord(
            id: animal.publicID,
            displayTagNumber: animal.displayTagNumber,
            displayTagColorID: animal.displayTagColorID,
            sex: animal.sex ?? .unknown,
            status: animal.status,
            isArchived: animal.isArchived,
            pastureID: animal.pasture?.publicID,
            pastureName: animal.pasture?.name,
            location: animal.location,
            lastPregnancyCheckDate: latestPregnancyCheck?.date,
            lastPregnancyStatus: pregnancyStatus(from: latestPregnancyCheck?.result),
            expectedCalvingDate: latestPregnancyCheck?.result == .pregnant ? expectedCalvingDate : nil,
            lastTreatmentDate: latestHealthRecord?.date
        )
    }

    static func makePastureRecord(from pasture: Pasture) -> DashboardPastureRecord {
        DashboardPastureRecord(
            id: pasture.publicID,
            name: pasture.name,
            acreage: pasture.acreage,
            usableAcreage: pasture.usableAcreage,
            targetAcresPerHead: pasture.targetAcresPerHead,
            activeAnimalCount: pasture.animals.filter { $0.isActiveInHerd }.count,
            lastGrazedDate: pasture.lastGrazedDate
        )
    }

    static func makeWorkingSessionRecord(from session: WorkingSession) -> DashboardWorkingSessionRecord {
        DashboardWorkingSessionRecord(
            id: session.publicID.uuidString,
            date: session.date,
            isActive: session.status == .active,
            sourcePastureName: session.sourcePasture?.name,
            protocolName: session.protocolName,
            totalQueueItems: session.queueItems.count,
            completedQueueItems: session.queueItems.filter { $0.status == .done }.count
        )
    }

    static func pregnancyStatus(from result: PregnancyResult?) -> DashboardPregnancyStatus? {
        guard let result else { return nil }

        switch result {
        case .open:
            return .open
        case .pregnant:
            return .pregnant
        case .unknown:
            return .unknown
        }
    }
}
