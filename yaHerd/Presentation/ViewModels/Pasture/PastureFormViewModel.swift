import Foundation
import Observation

@MainActor
@Observable
final class PastureFormViewModel {
    var name = ""
    var acreageText = ""
    var usableAcreageText = ""
    var targetAcresPerHeadText = ""
    var errorMessage: String?

    private var hasPreparedDefaultValues = false

    func prepareForCreate(
        defaultTargetAcresPerHead: Double,
        usableAcreagePercentDefault: Int
    ) {
        guard !hasPreparedDefaultValues else { return }
        hasPreparedDefaultValues = true

        if targetAcresPerHeadText.isEmpty, defaultTargetAcresPerHead > 0 {
            targetAcresPerHeadText = String(defaultTargetAcresPerHead)
        }

        if usableAcreageText.isEmpty,
           let acreage = parseDecimal(acreageText),
           acreage > 0,
           usableAcreagePercentDefault > 0 {
            let usable = acreage * (Double(usableAcreagePercentDefault) / 100)
            usableAcreageText = String(usable)
        }
    }

    func populate(from detail: PastureDetailSnapshot) {
        name = detail.name
        acreageText = Self.string(from: detail.acreage)
        usableAcreageText = Self.string(from: detail.usableAcreage)
        targetAcresPerHeadText = Self.string(from: detail.targetAcresPerHead)
        errorMessage = nil
    }

    var canSaveNewPasture: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        guard let acreage = parseDecimal(acreageText) else { return false }
        return acreage > 0
    }

    func makeCreateInput(
        defaultTargetAcresPerHead: Double,
        usableAcreagePercentDefault: Int
    ) throws -> PastureInput {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let acreage = parseDecimal(acreageText), acreage > 0 else {
            throw PastureValidationError.invalidAcreage
        }

        let usableAcreage: Double?
        if usableAcreageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            usableAcreage = acreage * (Double(usableAcreagePercentDefault) / 100)
        } else {
            usableAcreage = try parsePositiveOptional(
                usableAcreageText,
                error: .invalidUsableAcreage
            )
        }

        let targetAcresPerHead: Double?
        if targetAcresPerHeadText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            targetAcresPerHead = defaultTargetAcresPerHead > 0 ? defaultTargetAcresPerHead : nil
        } else {
            targetAcresPerHead = try parsePositiveOptional(
                targetAcresPerHeadText,
                error: .invalidTargetAcresPerHead
            )
        }

        return PastureInput(
            name: trimmedName,
            acreage: acreage,
            usableAcreage: usableAcreage,
            targetAcresPerHead: targetAcresPerHead
        )
    }

    func makeUpdateInput() throws -> PastureInput {
        PastureInput(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            acreage: try parsePositiveOptional(acreageText, error: .invalidAcreage),
            usableAcreage: try parsePositiveOptional(usableAcreageText, error: .invalidUsableAcreage),
            targetAcresPerHead: try parsePositiveOptional(
                targetAcresPerHeadText,
                error: .invalidTargetAcresPerHead
            )
        )
    }

    func parseDecimal(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "." else { return nil }
        if trimmed.hasSuffix("."), let value = Double(String(trimmed.dropLast())) {
            return value
        }
        return Double(trimmed)
    }

    private func parsePositiveOptional(
        _ text: String,
        error: PastureValidationError
    ) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = parseDecimal(trimmed), value > 0 else {
            throw error
        }
        return value
    }

    private static func string(from value: Double?) -> String {
        guard let value else { return "" }
        return String(value)
    }
}
