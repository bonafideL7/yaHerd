import SwiftUI

struct AnimalListInlineEntryRow: View {
    @Binding var text: String
    @Binding var sex: Sex
    @Binding var birthDate: Date
    @Binding var pastureID: UUID?
    @Binding var sireID: UUID?
    @Binding var sire: String
    @Binding var damID: UUID?
    @Binding var dam: String

    let mode: Mode
    let pastureOptions: [PastureOption]
    let helperText: String
    let focusRequestID: UUID
    let onSubmit: () -> Void
    let onPreparePicker: () -> Void
    let onShowBirthDatePicker: () -> Void
    let onRequestFocus: () -> Void
    let onShowDamPicker: () -> Void
    let onShowSirePicker: () -> Void
    let onCommitFocusLoss: () -> Void
    let onCancel: () -> Void
    let detailsAnimalID: UUID?
    let onOpenDetails: (UUID) -> Void

    @FocusState private var isFocused: Bool
    @State private var isParentsExpanded = false

    enum Mode: Hashable {
        case new
        case edit
    }

    private var placeholder: String {
        switch mode {
        case .new:
            return "Tag or name"
        case .edit:
            return "Edit tag or name"
        }
    }

    private var parentSummary: String {
        let selections = [
            dam.isEmpty ? nil : "Dam: \(dam)",
            sire.isEmpty ? nil : "Sire: \(sire)"
        ].compactMap { $0 }
        return selections.isEmpty ? "None selected" : selections.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .submitLabel(mode == .new ? .next : .done)
                    .focused($isFocused)
                    .onSubmit(onSubmit)
                    .onKeyPress(.delete) {
                        guard text.isEmpty else { return .ignored }
                        onCancel()
                        return .handled
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let detailsAnimalID {
                    Button {
                        onOpenDetails(detailsAnimalID)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open animal details")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                isFocused = true
            }

            if mode == .new {
                Text(helperText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isFocused = true
                    }
            }

            AnimalListInlineEntryAccessoryBar(
                text: $text,
                sex: $sex,
                birthDate: $birthDate,
                pastureID: $pastureID,
                pastureOptions: pastureOptions,
                isEditing: mode == .edit,
                parentSummary: parentSummary,
                onToggleParents: {
                    withAnimation(.snappy) { isParentsExpanded.toggle() }
                },
                onPreparePicker: onPreparePicker,
                onShowBirthDatePicker: onShowBirthDatePicker,
                onRequestFocus: onRequestFocus,
                onSubmit: onSubmit
            )

            if !isParentsExpanded && (!dam.isEmpty || !sire.isEmpty) {
                Text(parentSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy) { isParentsExpanded = true }
                    }
            }

            if isParentsExpanded {
                HStack(alignment: .top, spacing: 8) {
                    parentField(
                        title: "Dam",
                        value: dam,
                        onPick: onShowDamPicker,
                        onClear: { damID = nil; dam = "" }
                    )
                    parentField(
                        title: "Sire",
                        value: sire,
                        onPick: onShowSirePicker,
                        onClear: { sireID = nil; sire = "" }
                    )
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            // Handle taps on otherwise empty parts of the expanded row,
            // without intercepting taps on the contextual action buttons.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onTapGesture {
                    isFocused = true
                }
        }
        .task {
            isFocused = true
        }
        .onChange(of: focusRequestID) { _, _ in
            isFocused = true
        }
        .onChange(of: isFocused) { oldValue, newValue in
            if oldValue, !newValue {
                onCommitFocusLoss()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func parentField(
        title: String,
        value: String,
        onPick: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Button(action: onPick) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(value.isEmpty ? "Select" : value)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(title)")
            .accessibilityValue(value.isEmpty ? "None" : value)

            if !value.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 28, minHeight: 44)
                .accessibilityLabel("Clear \(title)")
            }
        }
        .padding(.horizontal, 10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity)
    }
}
