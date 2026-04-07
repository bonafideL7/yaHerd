import Foundation

struct CreatePastureUseCase {
    let repository: any PastureRepository

    func execute(input: PastureInput) throws -> PastureDetailSnapshot {
        let normalized = try validate(input: input, excluding: nil)
        return try repository.create(input: normalized)
    }

    private func validate(input: PastureInput, excluding id: UUID?) throws -> PastureInput {
        let normalized = input.normalized

        guard !normalized.name.isEmpty else {
            throw PastureValidationError.emptyName
        }

        if let acreage = normalized.acreage, acreage <= 0 {
            throw PastureValidationError.invalidAcreage
        }

        if let usableAcreage = normalized.usableAcreage, usableAcreage <= 0 {
            throw PastureValidationError.invalidUsableAcreage
        }

        if let targetAcresPerHead = normalized.targetAcresPerHead, targetAcresPerHead <= 0 {
            throw PastureValidationError.invalidTargetAcresPerHead
        }

        if let acreage = normalized.acreage,
           let usableAcreage = normalized.usableAcreage,
           usableAcreage > acreage {
            throw PastureValidationError.usableAcreageExceedsAcreage
        }

        if try repository.nameExists(normalized.name, excluding: id) {
            throw PastureValidationError.duplicateName(normalized.name)
        }

        return normalized
    }
}
