import Foundation

struct PastureInputValidator {
    private let nameExists: (String, UUID?) throws -> Bool

    init(nameExists: @escaping (String, UUID?) throws -> Bool) {
        self.nameExists = nameExists
    }

    init(repository: any PastureRepository) {
        self.nameExists = { name, id in
            try repository.nameExists(name, excluding: id)
        }
    }

    func validate(input: PastureInput, excluding id: UUID? = nil) throws -> PastureInput {
        let normalized = input.normalized

        guard Self.hasRequiredName(normalized.name) else {
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

        if try nameExists(normalized.name, id) {
            throw PastureValidationError.duplicateName(normalized.name)
        }

        return normalized
    }

    static func hasRequiredName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
