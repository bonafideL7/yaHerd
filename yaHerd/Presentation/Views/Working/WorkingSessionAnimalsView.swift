import SwiftUI

struct WorkingSessionAnimalsView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @StateObject private var viewModel: WorkingSessionDetailViewModel
    private let sessionID: UUID

    init(sessionID: UUID) {
        self.sessionID = sessionID
        _viewModel = StateObject(wrappedValue: WorkingSessionDetailViewModel(sessionID: sessionID, repository: EmptyWorkingRepository()))
    }

    private var orderedItems: [WorkingQueueItemSnapshot] {
        viewModel.session?.queueItems.sorted { $0.queueOrder < $1.queueOrder } ?? []
    }

    var body: some View {
        List {
            if orderedItems.isEmpty {
                ContentUnavailableView(
                    "No animals",
                    systemImage: "list.bullet",
                    description: Text("Collect animals into the working pen to start a queue.")
                )
            } else {
                ForEach(orderedItems) { item in
                    NavigationLink {
                        WorkingSessionAnimalEditView(sessionID: sessionID, queueItemID: item.id)
                    } label: {
                        row(for: item)
                    }
                }
            }
        }
        .navigationTitle("Animals")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(repository: dependencies.workingRepository)
            viewModel.load()
        }
    }

    @ViewBuilder
    private func row(for item: WorkingQueueItemSnapshot) -> some View {
        if let tagNumber = item.animalDisplayTagNumber {
            HStack(spacing: 12) {
                let def = tagColorLibrary.resolvedDefinition(tagColorID: item.animalDisplayTagColorID)
                VStack(alignment: .leading, spacing: 6) {
                    AnimalTagView(
                        tagNumber: tagNumber,
                        color: def.color,
                        colorName: def.name
                    )
                    Text(item.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if item.status == .done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if item.status == .skipped {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Missing animal")
                .foregroundStyle(.secondary)
        }
    }
}
