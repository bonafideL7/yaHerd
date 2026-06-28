import Foundation

struct AnimalInlineEntryResult: Hashable {
    let rawText: String
    let name: String
    let tagNumber: String
    let tagColorID: UUID?

    var isEmpty: Bool {
        name.isEmpty && tagNumber.isEmpty
    }
}

enum AnimalInlineEntryParser {
    static func parse(_ text: String, colors: [TagColorSnapshot]) -> AnimalInlineEntryResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AnimalInlineEntryResult(rawText: trimmed, name: "", tagNumber: "", tagColorID: nil)
        }

        if trimmed.isOnlyDigits {
            return AnimalInlineEntryResult(rawText: trimmed, name: "", tagNumber: trimmed, tagColorID: nil)
        }

        let uppercasedText = trimmed.uppercased()
        let definitions = colors
            .enumerated()
            .map { index, definition in
                (
                    id: definition.id,
                    prefix: definition.prefix.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                    index: index
                )
            }
            .filter { !$0.prefix.isEmpty }
            .sorted { lhs, rhs in
                if lhs.prefix.count != rhs.prefix.count {
                    return lhs.prefix.count > rhs.prefix.count
                }
                return lhs.index < rhs.index
            }

        for definition in definitions where uppercasedText.hasPrefix(definition.prefix) {
            let numberStart = trimmed.index(trimmed.startIndex, offsetBy: definition.prefix.count)
            let number = String(trimmed[numberStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !number.isEmpty, number.isOnlyDigits else { continue }

            return AnimalInlineEntryResult(
                rawText: trimmed,
                name: "",
                tagNumber: number,
                tagColorID: definition.id
            )
        }

        return AnimalInlineEntryResult(rawText: trimmed, name: trimmed, tagNumber: "", tagColorID: nil)
    }

    @MainActor
    static func editableText(for animal: AnimalSummary, tagColorLibrary: TagColorLibraryStore) -> String {
        let tagNumber = animal.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tagNumber.isEmpty {
            return tagColorLibrary.formattedTag(tagNumber: tagNumber, colorID: animal.displayTagColorID)
        }

        return animal.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var isOnlyDigits: Bool {
        !isEmpty && unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }
}
