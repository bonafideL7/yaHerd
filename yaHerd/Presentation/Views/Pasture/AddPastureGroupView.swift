import SwiftUI

struct AddPastureGroupView: View {
    let onSave: (() -> Void)?

    init(onSave: (() -> Void)? = nil) {
        self.onSave = onSave
    }

    var body: some View {
        PastureGroupEditorView(onSave: onSave)
    }
}
