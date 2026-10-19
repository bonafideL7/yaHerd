//
//  ToolbarIconButtons.swift
//  yaHerd
//

import SwiftUI

struct ToolbarSaveButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    init(accessibilityLabel: String = "Save", action: @escaping () -> Void) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        RoleIconButton(
            role: .confirm,
            accessibilityLabel: accessibilityLabel,
            action: action
        )
        .disabledWhenDataReadOnly()
    }
}

struct ToolbarDoneButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    init(accessibilityLabel: String = "Done", action: @escaping () -> Void) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        RoleIconButton(
            role: .confirm,
            accessibilityLabel: accessibilityLabel,
            action: action
        )
    }
}


struct ToolbarCancelButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    init(accessibilityLabel: String = "Cancel", action: @escaping () -> Void) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        RoleIconButton(
            role: .cancel,
            accessibilityLabel: accessibilityLabel,
            action: action
        )
    }
}

struct ToolbarCloseButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    init(accessibilityLabel: String = "Close", action: @escaping () -> Void) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(role: .close) {
            action()
        }
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

private struct RoleIconButton: View {
    let role: ButtonRole
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(role: role) {
            action()
        }
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

struct ToolbarEditButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    init(accessibilityLabel: String = "Edit", action: @escaping () -> Void) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
        }
        .accessibilityLabel(Text(accessibilityLabel))
        .disabledWhenDataReadOnly()
    }
}
