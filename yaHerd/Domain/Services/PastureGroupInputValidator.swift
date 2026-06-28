import Foundation

struct PastureGroupInputValidator {
    static let grazeDaysRange = 1...30
    static let restDaysRange = 7...90

    private let groupNameExists: (String) throws -> Bool

    init(groupNameExists: @escaping (String) throws -> Bool) {
        self.groupNameExists = groupNameExists
    }

    init(repository: any PastureGroupNameChecking) {
        self.groupNameExists = { name in
            try repository.groupNameExists(name)
        }
    }

    func validate(input: PastureGroupInput) throws -> PastureGroupInput {
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

        if try groupNameExists(normalized.name) {
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
