import SwiftUI

struct AnimalListInlineEntryRow: View {
    @Binding var text: String
    @Binding var sex: Sex
    @Binding var birthDate: Date
    @Binding var pastureID: UUID?

    let mode: Mode
    let pastureOptions: [PastureOption]
    let helperText: String
    let focusRequestID: UUID
    let onSubmit: () -> Void
    let onCommitFocusLoss: () -> Void
    let onCancel: () -> Void
    let detailsAnimalID: UUID?
    let onOpenDetails: (UUID) -> Void

    @FocusState private var isFocused: Bool

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

            if mode == .new {
                Text(helperText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
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
}
