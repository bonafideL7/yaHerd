import Foundation

struct PastureGroupInputValidator {
    static let grazeDaysRange = 1...30
    static let restDaysRange = 7...90

    private let groupNameExists: (String, UUID?) throws -> Bool

    init(groupNameExists: @escaping (String, UUID?) throws -> Bool) {
        self.groupNameExists = groupNameExists
    }

    init(repository: any PastureGroupNameChecking) {
        self.groupNameExists = { name, excludedID in
            try repository.groupNameExists(name, excluding: excludedID)
        }
    }

    func validate(input: PastureGroupInput, excluding excludedID: UUID? = nil) throws -> PastureGroupInput {
        let normalized = input.normalized

        guard PastureInputValidator.hasRequiredName(normalized.name) else {
            throw PastureValidationError.emptyName
        }

        guard Self.grazeDaysRange.contains(normalized.grazeDays) else {
            throw PastureValidationError.invalidGrazeDays
        }

        guard Self.restDaysRange.contains(normalized.restDays) else {
            throw PastureValidationError.invalidRestDays
        }

        if try groupNameExists(normalized.name, excludedID) {
            throw PastureValidationError.duplicateName(normalized.name)
        }

        return normalized
    }

    static func canAttemptSave(name: String, grazeDays: Int, restDays: Int) -> Bool {
        PastureInputValidator.hasRequiredName(name)
            && grazeDaysRange.contains(grazeDays)
            && restDaysRange.contains(restDays)
    }
}
