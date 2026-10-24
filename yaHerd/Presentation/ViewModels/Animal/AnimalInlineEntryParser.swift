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

        let identifiers = colors
            .enumerated()
            .flatMap { index, definition in
                [
                    (id: definition.id, value: definition.prefix, index: index, isPrefix: true),
                    (id: definition.id, value: definition.name, index: index, isPrefix: false)
                ]
            }
            .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count > rhs.value.count
                }
                if lhs.isPrefix != rhs.isPrefix {
                    return lhs.isPrefix
                }
                return lhs.index < rhs.index
            }

        for identifier in identifiers {
            guard let match = trimmed.range(of: identifier.value, options: [.anchored, .caseInsensitive]) else {
                continue
            }
            let number = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard number.isOnlyDigits else { continue }

            return AnimalInlineEntryResult(
                rawText: trimmed,
                name: "",
                tagNumber: number,
                tagColorID: identifier.id
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
