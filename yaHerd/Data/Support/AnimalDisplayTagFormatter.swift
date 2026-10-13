import Foundation

enum AnimalDisplayTagFormatter {
    static let untaggedPlaceholder = "UT"

    static func displayTagNumber(from tagNumber: String) -> String {
        let trimmedTagNumber = tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTagNumber.isEmpty ? untaggedPlaceholder : tagNumber
    }
}
