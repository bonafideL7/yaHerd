import Foundation

struct CreateFieldCheckSessionUseCase {
    let repository: any FieldCheckRepository

    func execute(input: FieldCheckSessionStartInput) throws -> UUID {
        try repository.createSession(input: input)
    }
}
