import Foundation

struct CreateFieldCheckSessionUseCase {
    let repository: any FieldCheckSessionCreating

    func execute(input: FieldCheckSessionStartInput) throws -> UUID {
        try repository.createSession(input: input)
    }
}
