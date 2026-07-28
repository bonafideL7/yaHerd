import SwiftUI

enum WorkingSessionAnimalFilter: String, CaseIterable, Identifiable {
    case remaining
    case all
    case completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .remaining:
            return "Remaining"
        case .all:
            return "All"
        case .completed:
            return "Completed"
        }
    }

    var systemImage: String {
        switch self {
        case .remaining:
            return "circle.dotted"
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .completed:
            return "checkmark.circle"
        }
    }

    func includes(_ status: WorkingQueueStatus) -> Bool {
        switch self {
        case .remaining:
            return status != .done
        case .all:
            return true
        case .completed:
            return status == .done
        }
    }
}

struct WorkingSessionProgressHeader: View {
    let session: WorkingSessionDetailSnapshot

    private var totalCount: Int {
        session.queueItems.count
    }

    private var remainingCount: Int {
        max(0, totalCount - session.doneCount)
    }

    private var remainingText: String {
        remainingCount == 1 ? "1 remaining" : "\(remainingCount) remaining"
    }

    private var treatmentText: String {
        let count = session.plannedTreatments.count
        if count == 0 { return "No planned treatments" }
        return count == 1 ? "1 planned treatment" : "\(count) planned treatments"
    }

    private var isComplete: Bool {
        totalCount > 0 && remainingCount == 0
    }

    private var statusTint: Color {
        isComplete ? Color.secondary : Color.orange
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(session.doneCount)/\(totalCount)")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text("worked")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text("\(remainingText) • \(treatmentText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let pastureName = session.sourcePastureName {
                    Text("From \(pastureName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: isComplete ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isComplete ? Color.green : Color.orange)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct WorkingSessionCompletedReviewHeader: View {
    let session: WorkingSessionDetailSnapshot

    private var totalCount: Int {
        session.queueItems.count
    }

    private var notWorkedCount: Int {
        max(0, totalCount - session.doneCount)
    }

    private var statusLabel: String {
        switch session.status {
        case .finished:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        case .active:
            return "Active"
        }
    }

    private var statusImage: String {
        switch session.status {
        case .finished:
            return "checkmark.seal.fill"
        case .cancelled:
            return "xmark.octagon.fill"
        case .active:
            return "circle.dotted"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label(statusLabel, systemImage: statusImage)
                    .font(.headline)

                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let pastureName = session.sourcePastureName {
                    Text(pastureName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    Label("\(session.doneCount) worked", systemImage: "checkmark.circle")
                    Label("\(notWorkedCount) not worked", systemImage: "circle")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "lock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Read only")
        }
        .padding(.vertical, 2)
    }
}

struct WorkingSessionAnimalFilterRow: View {
    @Binding var selectedFilter: WorkingSessionAnimalFilter
    let visibleCount: Int
    let totalCount: Int
    let hasSearchText: Bool
    let onReset: () -> Void

    private var countText: String {
        guard totalCount > 0 else { return "No animals" }
        return visibleCount == totalCount ? "\(totalCount) animals" : "\(visibleCount) of \(totalCount)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Animal Filter", selection: $selectedFilter) {
                    ForEach(WorkingSessionAnimalFilter.allCases) { filter in
                        Label(filter.label, systemImage: filter.systemImage)
                            .tag(filter)
                    }
                }

                if selectedFilter != .all || hasSearchText {
                    Section {
                        Button(action: onReset) {
                            Label("Show All Animals", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            } label: {
                Label(selectedFilter.label, systemImage: selectedFilter.systemImage)
                    .font(.subheadline.weight(.semibold))
            }

            Spacer(minLength: 12)

            Text(countText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Animal filter, \(selectedFilter.label), \(countText)")
    }
}

struct WorkingSessionAnimalRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    let item: WorkingQueueItemSnapshot
    var showsDestination = false

    private var statusLabel: String {
        switch item.status {
        case .queued:
            return "Not worked"
        case .inProgress:
            return "In progress"
        case .done:
            return "Worked"
        case .skipped:
            return "Not worked"
        }
    }

    private var statusIcon: String {
        switch item.status {
        case .queued:
            return "circle"
        case .inProgress:
            return "circle.dashed"
        case .done:
            return "checkmark.circle.fill"
        case .skipped:
            return "minus.circle"
        }
    }

    private var statusTint: Color {
        switch item.status {
        case .done:
            return .green
        case .inProgress, .skipped:
            return .orange
        case .queued:
            return .secondary
        }
    }

    private var detailText: String {
        var parts = [item.animalSex.label, statusLabel]
        if showsDestination {
            parts.append(item.destinationPastureName ?? "No destination")
        }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        HStack(spacing: 12) {
            if let tagNumber = item.animalDisplayTagNumber {
                let tagDefinition = tagColorLibrary.resolvedDefinition(
                    tagColorID: item.animalDisplayTagColorID
                )
                let damTagDefinition = tagColorLibrary.resolvedDefinition(
                    tagColorID: item.animalDamDisplayTagColorID
                )

                VStack(alignment: .leading, spacing: 6) {
                    AnimalTagView(
                        tagNumber: tagNumber,
                        color: tagDefinition.color,
                        colorName: tagDefinition.name,
                        damTagNumber: item.animalDamDisplayTagNumber,
                        damTagColor: damTagDefinition.color,
                        damTagColorName: damTagDefinition.name
                    )

                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Missing Animal")
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: statusIcon)
                .foregroundStyle(statusTint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
