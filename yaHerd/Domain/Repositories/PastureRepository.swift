import Foundation

protocol PastureRepository {
    func fetchPastures() throws -> [PastureSummary]
    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot?
    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool
    @discardableResult
    func create(input: PastureInput) throws -> PastureDetailSnapshot
    @discardableResult
    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot
    func delete(ids: [UUID]) throws
}
