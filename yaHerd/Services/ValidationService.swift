//
//  ValidationService.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import Foundation
import SwiftData

struct ValidationService {

    // MARK: - Animal Validation
    static func validateAnimal(
        tagNumber: String,
        tagColorID: UUID?,
        birthDate: Date,
        context: ModelContext,
        existing: Animal? = nil
    ) throws {
        try validateTagNumber(tagNumber)
        try validateActiveTagUniqueness(
            tagNumber: tagNumber,
            tagColorID: tagColorID,
            context: context,
            existingAnimal: existing
        )

        // Birthdate cannot be in the future
        if birthDate > Date() {
            throw ValidationError("Birth date cannot be in the future.")
        }
    }

    static func validateAnimalTag(
        number: String,
        colorID: UUID?,
        animal: Animal,
        context: ModelContext,
        existingTag: AnimalTag? = nil,
        isActive: Bool = true
    ) throws {
        try validateTagNumber(number)

        guard isActive else { return }

        try validateActiveTagUniqueness(
            tagNumber: number,
            tagColorID: colorID,
            context: context,
            existingAnimal: animal,
            existingTag: existingTag
        )
    }

    private static func validateTagNumber(_ tagNumber: String) throws {
        guard !tagNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("Tag number is required.")
        }
    }

    private static func validateActiveTagUniqueness(
        tagNumber: String,
        tagColorID: UUID?,
        context: ModelContext,
        existingAnimal: Animal? = nil,
        existingTag: AnimalTag? = nil
    ) throws {
        let trimmedNumber = tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNumber.isEmpty else { return }

        let descriptor = FetchDescriptor<AnimalTag>()
        let allTags = (try? context.fetch(descriptor)) ?? []

        let conflict = allTags.first { tag in
            guard tag.isActive else { return false }
            guard tag.normalizedNumber.caseInsensitiveCompare(trimmedNumber) == .orderedSame else { return false }
            guard tag.colorID == tagColorID else { return false }

            if let existingTag,
               tag.persistentModelID == existingTag.persistentModelID {
                return false
            }

            guard let otherAnimal = tag.animal else { return false }
            guard otherAnimal.status == .alive else { return false }

            if let existingAnimal,
               otherAnimal.persistentModelID == existingAnimal.persistentModelID {
                return false
            }

            return true
        }

        if conflict != nil {
            throw ValidationError("That active tag color and number combination is already assigned to another active animal.")
        }
    }


    // MARK: - Health Record Validation
    static func validateHealthRecord(
        treatment: String
    ) throws {
        guard !treatment.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError("Treatment description is required.")
        }
    }


    // MARK: - Pregnancy Check Validation
    static func validatePregCheck() throws {
        // Add rules later if needed:
        // Example: ensure date is not in the future
    }


    // For throwing human-readable errors
    struct ValidationError: LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
