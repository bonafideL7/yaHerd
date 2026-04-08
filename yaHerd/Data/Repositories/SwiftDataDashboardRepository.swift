import Foundation
import SwiftData

struct SwiftDataDashboardRepository: DashboardRepository {
    let context: ModelContext

    func fetchDashboardRecords() throws -> DashboardRecords {
        let animalDescriptor = FetchDescriptor<Animal>()
        let pastureDescriptor = FetchDescriptor<Pasture>(sortBy: [SortDescriptor(\Pasture.name)])
        let workingDescriptor = FetchDescriptor<WorkingSession>(sortBy: [SortDescriptor(\WorkingSession.date, order: .reverse)])

        let animals = try context.fetch(animalDescriptor).map(makeAnimalRecord)
        let pastures = try context.fetch(pastureDescriptor).map(makePastureRecord)
        let sessions = try context.fetch(workingDescriptor).map(makeWorkingSessionRecord)

        return DashboardRecords(
            animals: animals,
            pastures: pastures,
            workingSessions: sessions
        )
    }

    func markPastureGrazedToday(id: UUID, on date: Date) throws {
        let descriptor = FetchDescriptor<Pasture>(
            predicate: #Predicate<Pasture> { pasture in
                pasture.publicID == id
            }
        )

        guard let pasture = try context.fetch(descriptor).first else { return }
        pasture.lastGrazedDate = date
        try context.save()
    }

    private func makeAnimalRecord(from animal: Animal) -> DashboardAnimalRecord {
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
            sex: animal.sex ?? .female,
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

    private func makePastureRecord(from pasture: Pasture) -> DashboardPastureRecord {
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

    private func makeWorkingSessionRecord(from session: WorkingSession) -> DashboardWorkingSessionRecord {
        DashboardWorkingSessionRecord(
            id: sessionIdentifier(for: session),
            date: session.date,
            isActive: session.status == .active,
            sourcePastureName: session.sourcePasture?.name,
            protocolName: session.protocolName,
            totalQueueItems: session.queueItems.count,
            completedQueueItems: session.queueItems.filter { $0.status == .done }.count
        )
    }

    private func pregnancyStatus(from result: PregnancyResult?) -> DashboardPregnancyStatus? {
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

    private func sessionIdentifier(for session: WorkingSession) -> String {
        "\(session.date.timeIntervalSinceReferenceDate)-\(session.protocolName)-\(session.sourcePasture?.name ?? "")"
    }
}
