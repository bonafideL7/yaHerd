import Foundation

struct CreateWorkingSessionUseCase {
    let repository: any WorkingRepository

    func execute(date: Date, sourcePastureID: UUID?, protocolName: String, protocolItems: [WorkingProtocolItem]) throws -> UUID {
        try repository.createSession(date: date, sourcePastureID: sourcePastureID, protocolName: protocolName, protocolItems: protocolItems)
    }
}
