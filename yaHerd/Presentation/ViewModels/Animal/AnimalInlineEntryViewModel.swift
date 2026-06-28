import Foundation
import Observation

@MainActor
@Observable
final class AnimalInlineEntryViewModel {
    @ObservationIgnored private let dateProvider: any DateProviding
    @ObservationIgnored private let calendar: Calendar

    var isActive = false
    var identity = UUID()
    var editingAnimalID: UUID?
    var text = ""
    var sex: Sex = .unknown
    var birthDate: Date
    var pastureID: UUID?
    var focusRequestID = UUID()
    var isCommitting = false
    var ignoresNextFocusLoss = false

    init(
        dateProvider: any DateProviding = SystemDateProvider(),
        calendar: Calendar = .current
    ) {
        self.dateProvider = dateProvider
        self.calendar = calendar
        self.birthDate = calendar.startOfDay(for: dateProvider.now)
    }

    var isEditing: Bool {
        editingAnimalID != nil
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func beginNew() {
        editingAnimalID = nil
        isActive = true
        identity = UUID()
        text = ""
        sex = .unknown
        birthDate = defaultBirthDate
        pastureID = nil
        ignoresNextFocusLoss = false
    }

    func beginEditing(_ animal: AnimalSummary, tagColorLibrary: TagColorLibraryStore) {
        editingAnimalID = animal.id
        isActive = true
        identity = animal.id
        ignoresNextFocusLoss = false
        text = AnimalInlineEntryParser.editableText(for: animal, tagColorLibrary: tagColorLibrary)
        sex = animal.sex
        birthDate = animal.birthDate
        pastureID = animal.pastureID
    }

    func requestFocus() {
        guard isActive else { return }
        DispatchQueue.main.async {
            self.focusRequestID = UUID()
        }
    }

    func prepareForPickerPresentation() {
        ignoresNextFocusLoss = true
    }

    func shouldCommitAfterFocusLoss() -> Bool {
        if ignoresNextFocusLoss {
            ignoresNextFocusLoss = false
            return false
        }
        return true
    }

    func cancel() {
        isActive = false
        editingAnimalID = nil
        text = ""
        sex = .unknown
        birthDate = defaultBirthDate
        pastureID = nil
        identity = UUID()
        ignoresNextFocusLoss = false
    }

    @discardableResult
    func commit(
        startNewEntryAfterCreate: Bool,
        colors: [TagColorSnapshot],
        defaultTagColorID: UUID?,
        using repository: any AnimalListRepository
    ) throws -> Bool {
        guard isActive, !isCommitting else { return false }

        let trimmedText = trimmedText
        guard !trimmedText.isEmpty else {
            if !startNewEntryAfterCreate {
                cancel()
            }
            return false
        }

        isCommitting = true
        defer { isCommitting = false }

        if let editingAnimalID {
            try updateInlineAnimal(id: editingAnimalID, text: trimmedText, colors: colors, defaultTagColorID: defaultTagColorID, using: repository)
            clearCommittedEntry()
        } else {
            try createInlineAnimal(text: trimmedText, colors: colors, defaultTagColorID: defaultTagColorID, using: repository)
            if startNewEntryAfterCreate {
                beginNew()
            } else {
                clearCommittedEntry()
            }
        }

        return true
    }

    private func createInlineAnimal(
        text: String,
        colors: [TagColorSnapshot],
        defaultTagColorID: UUID?,
        using repository: any AnimalListRepository
    ) throws {
        let parsed = AnimalInlineEntryParser.parse(text, colors: colors)
        guard !parsed.isEmpty else { return }

        _ = try CreateInlineAnimalUseCase(repository: repository).execute(
            name: parsed.name,
            tagNumber: parsed.tagNumber,
            tagColorID: parsed.tagNumber.isEmpty ? nil : (parsed.tagColorID ?? defaultTagColorID),
            sex: sex,
            birthDate: birthDate,
            pastureID: pastureID
        )
    }

    private func updateInlineAnimal(
        id: UUID,
        text: String,
        colors: [TagColorSnapshot],
        defaultTagColorID: UUID?,
        using repository: any AnimalListRepository
    ) throws {
        let parsed = AnimalInlineEntryParser.parse(text, colors: colors)

        _ = try UpdateInlineAnimalUseCase(repository: repository).execute(
            id: id,
            name: parsed.tagNumber.isEmpty ? parsed.name : nil,
            tagNumber: parsed.tagNumber.isEmpty ? nil : parsed.tagNumber,
            tagColorID: parsed.tagNumber.isEmpty ? nil : (parsed.tagColorID ?? defaultTagColorID),
            sex: sex,
            birthDate: birthDate,
            pastureID: pastureID
        )
    }

    private var defaultBirthDate: Date {
        calendar.startOfDay(for: dateProvider.now)
    }

    private func clearCommittedEntry() {
        isActive = false
        editingAnimalID = nil
        text = ""
        sex = .unknown
        birthDate = defaultBirthDate
        pastureID = nil
        identity = UUID()
        ignoresNextFocusLoss = false
    }
}
