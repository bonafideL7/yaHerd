import SwiftUI

struct PastureGroupListView: View {
    @Environment(\.pastureGroupListRepository) private var repository
    @State private var model = PastureGroupListViewModel()

    var body: some View {
        Group {
            if model.groups.isEmpty {
                ContentUnavailableView(
                    "No Pasture Groups",
                    systemImage: "rectangle.3.group",
                    description: Text("Create groups to organize pastures by grazing and rest schedules.")
                )
            } else {
                List {
                    ForEach(model.groups) { group in
                        NavigationLink {
                            PastureGroupDetailView(groupID: group.id)
                        } label: {
                            PastureGroupRow(group: group)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                model.requestDelete(group)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Pasture Groups")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: model.requestAddGroup) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Pasture Group")
            }
        }
        .sheet(isPresented: $model.isPresentingAddGroup) {
            AddPastureGroupView {
                model.load(using: repository)
            }
        }
        .confirmationDialog(
            "Delete Pasture Group?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            if let group = model.groupPendingDeletion {
                Button("Delete \(group.name)", role: .destructive) {
                    model.deleteGroup(id: group.id, using: repository)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let group = model.groupPendingDeletion {
                Text("This will remove \(group.name) and unassign its pastures from the group. The pastures will not be deleted.")
            } else {
                Text("The pastures in this group will not be deleted.")
            }
        }
        .task {
            model.load(using: repository)
        }
        .alert("Can’t Complete Request", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.clearError()
                }
            }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.groupPendingDeletion != nil },
            set: { newValue in
                if !newValue {
                    model.clearPendingDeletion()
                }
            }
        )
    }
}

private struct PastureGroupRow: View {
    let group: PastureGroupSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.name)
                .font(.headline)
            Text("\(group.pastureCount) pastures • Graze \(group.grazeDays)d • Rest \(group.restDays)d")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
