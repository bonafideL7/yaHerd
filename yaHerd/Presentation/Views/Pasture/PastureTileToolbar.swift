import SwiftUI

struct PastureTileToolbar: View {
    @Binding var filter: PastureListFilter
    let isManaging: Bool
    let onToggleManageMode: () -> Void
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
                    FieldChecksView(mode: .all)
                } label: {
                    Label("Pasture Checks", systemImage: "checklist")
                }

                NavigationLink {
                    WorkingSessionsView()
                } label: {
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
