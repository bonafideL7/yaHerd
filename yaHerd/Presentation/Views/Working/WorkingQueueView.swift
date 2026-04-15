import SwiftUI

struct WorkingQueueView: View {
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
            Section {
                ForEach(orderedItems) { item in
                    NavigationLink {
                        WorkingChuteView(sessionID: sessionID, queueItemID: item.id)
                    } label: {
                        WorkingQueueRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(repository: dependencies.workingRepository)
            viewModel.load()
        }
    }
}

private struct WorkingQueueRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    let item: WorkingQueueItemSnapshot

    private var statusIcon: String {
        switch item.status {
        case .queued: return "circle"
        case .inProgress: return "circle.dashed"
        case .done: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(item.status == .done ? .green : item.status == .skipped ? .orange : .secondary)

            if let tagNumber = item.animalDisplayTagNumber {
                let def = tagColorLibrary.resolvedDefinition(tagColorID: item.animalDisplayTagColorID)
                VStack(alignment: .leading, spacing: 6) {
                    AnimalTagView(
                        tagNumber: tagNumber,
                        color: def.color,
                        colorName: def.name
                    )
                    Text(item.animalSex.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Missing animal")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
