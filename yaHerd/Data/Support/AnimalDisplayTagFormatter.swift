import Foundation

enum AnimalDisplayTagFormatter {
    static let untaggedPlaceholder = "UT"

    static func displayTagNumber(for animal: Animal?) -> String? {
        guard let animal else { return nil }
        return displayTagNumber(from: animal.displayTagNumber)
    }

    static func displayTagNumber(from tagNumber: String) -> String {
        let trimmedTagNumber = tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTagNumber.isEmpty ? untaggedPlaceholder : tagNumber
    }
}
