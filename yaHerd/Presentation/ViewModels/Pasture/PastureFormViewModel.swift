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

    var shouldShowStockingFields: Bool {
        guard let acreage = parseDecimal(acreageText) else { return false }
        return acreage > 1
    }
    
    var canSaveNewPasture: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        
        return true
    }
    
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
    
    func makeCreateInput(
        defaultTargetAcresPerHead: Double,
        usableAcreagePercentDefault: Int
    ) throws -> PastureInput {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let acreage = try parsePositiveOptional(acreageText, error: .invalidAcreage)
        
        let shouldSaveStocking = (acreage ?? 0) > 1
        
        let usableAcreage: Double?
        if shouldSaveStocking {
            if usableAcreageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let acreage {
                    usableAcreage = acreage * (Double(usableAcreagePercentDefault) / 100)
                } else {
                    usableAcreage = nil
                }
            } else {
                usableAcreage = try parsePositiveOptional(
                    usableAcreageText,
                    error: .invalidUsableAcreage
                )
            }
        } else {
            usableAcreage = nil
        }
        
        let targetAcresPerHead: Double?
        if shouldSaveStocking {
            if targetAcresPerHeadText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                targetAcresPerHead = defaultTargetAcresPerHead > 0 ? defaultTargetAcresPerHead : nil
            } else {
                targetAcresPerHead = try parsePositiveOptional(
                    targetAcresPerHeadText,
                    error: .invalidTargetAcresPerHead
                )
            }
        } else {
            targetAcresPerHead = nil
        }
        
        return PastureInput(
            name: trimmedName,
            acreage: acreage,
            usableAcreage: usableAcreage,
            targetAcresPerHead: targetAcresPerHead
        )
    }

    func makeUpdateInput() throws -> PastureInput {
        let acreage = try parsePositiveOptional(acreageText, error: .invalidAcreage)
        let shouldSaveStocking = (acreage ?? 0) > 1
        
        return PastureInput(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            acreage: acreage,
            usableAcreage: shouldSaveStocking
            ? try parsePositiveOptional(usableAcreageText, error: .invalidUsableAcreage)
            : nil,
            targetAcresPerHead: shouldSaveStocking
            ? try parsePositiveOptional(targetAcresPerHeadText, error: .invalidTargetAcresPerHead)
            : nil
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
