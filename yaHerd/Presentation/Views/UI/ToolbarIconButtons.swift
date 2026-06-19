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
        if #available(iOS 26.0, *) {
            RoleIconButton(
                role: .confirm,
                fallbackSystemImage: "checkmark",
                accessibilityLabel: accessibilityLabel,
                action: action
            )
        } else {
            ToolbarCircularIconButton(
                systemImage: "checkmark",
                accessibilityLabel: accessibilityLabel,
                isProminent: true,
                action: action
            )
        }
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
        if #available(iOS 26.0, *) {
            RoleIconButton(
                role: .confirm,
                fallbackSystemImage: "checkmark",
                accessibilityLabel: accessibilityLabel,
                action: action
            )
        } else {
            ToolbarCircularIconButton(
                systemImage: "checkmark",
                accessibilityLabel: accessibilityLabel,
                isProminent: true,
                action: action
            )
        }
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
            fallbackSystemImage: "xmark",
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
        if #available(iOS 26.0, *) {
            Button(role: .close) {
                action()
            }
            .accessibilityLabel(Text(accessibilityLabel))
        } else {
            Button(action: action) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(Text(accessibilityLabel))
            .modifier(ToolbarCircularButtonModifier(isProminent: false))
        }
    }
}

private struct RoleIconButton: View {
    let role: ButtonRole
    let fallbackSystemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: role) {
                action()
            }
            .accessibilityLabel(Text(accessibilityLabel))
        } else {
            Button(action: action) {
                Image(systemName: fallbackSystemImage)
            }
            .accessibilityLabel(Text(accessibilityLabel))
            .modifier(ToolbarCircularButtonModifier(isProminent: false))
        }
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
        ToolbarCircularIconButton(
            systemImage: "pencil",
            accessibilityLabel: accessibilityLabel,
            isProminent: false,
            action: action
        )
    }
}

private struct ToolbarCircularIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .accessibilityLabel(Text(accessibilityLabel))
        .modifier(ToolbarCircularButtonModifier(isProminent: isProminent))
    }
}

private struct ToolbarCircularButtonModifier: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if isProminent {
            content
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
        }
    }
}
