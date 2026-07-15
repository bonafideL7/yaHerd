import SwiftUI

struct PastureTileToolbar: View {
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Binding var filter: PastureListFilter
    let isManaging: Bool
    let onToggleManageMode: () -> Void
    let onOpenFieldChecks: () -> Void
    let onOpenWorkSessions: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        if isManaging {
            Button(action: onToggleManageMode) {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Done Managing")
        } else {
            Menu {
                Button(action: onToggleManageMode) {
                    Label("Manage Pastures", systemImage: "line.3.horizontal.decrease.circle")
                }
                .disabled(!dataAccessMode.allowsDataMutations)

                Divider()

                Picker("Filter", selection: $filter) {
                    ForEach(PastureListFilter.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }

                if filter != .all {
                    Button {
                        filter = .all
                    } label: {
                        Label("Clear Filter", systemImage: "xmark.circle")
                    }
                }

                Divider()

                NavigationLink {
                    PastureGroupListView()
                } label: {
                    Label("Pasture Groups", systemImage: "rectangle.3.group")
                }

                Button(action: onOpenFieldChecks) {
                    Label("Pasture Checks", systemImage: "checklist")
                }

                Button(action: onOpenWorkSessions) {
                    Label("Working Sessions", systemImage: "wrench.and.screwdriver")
                }

                Divider()

                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Pasture list actions")
        }
    }
}
