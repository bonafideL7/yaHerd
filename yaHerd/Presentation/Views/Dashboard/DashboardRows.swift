import LucideIcons
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DashboardActiveSessionCard: View {
    let session: DashboardWorkingSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(.tint)
                Text(session.protocolName)
                    .font(.headline)
                Spacer()
                Text("In progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let sourcePastureName = session.sourcePastureName, !sourcePastureName.isEmpty {
                Text("Source pasture: \(sourcePastureName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct DashboardAlertRow: View {
    let alert: DashboardAlert
    let colorForSeverity: (DashboardAlertSeverity) -> Color

    var body: some View {
        HStack(spacing: 12) {
            if let icon = UIImage(lucideId: alert.icon) {
                Image(uiImage: icon.scaled(to: CGSize(width: 22, height: 22)))
                    .renderingMode(.template)
                    .foregroundStyle(colorForSeverity(alert.severity))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.headline)
                if let message = alert.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct DashboardAnimalRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let animal: DashboardAnimalItem

    var body: some View {
        HStack(spacing: 12) {
            let definition = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)

            VStack(alignment: .leading, spacing: 6) {
                AnimalTagView(
                    tagNumber: animal.displayTagNumber,
                    color: definition.color,
                    colorName: definition.name
                )

                HStack(spacing: 6) {
                    Text(animal.sex.label)
                    if animal.location == .workingPen {
                        Text("• Working Pen")
                    } else if let pastureName = animal.pastureName {
                        Text("• \(pastureName)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct DashboardPastureRow: View {
    let pasture: DashboardPastureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(pasture.name)
                    .font(.headline)

                Spacer()

                if pasture.isOverstocked {
                    Label("Over", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if pasture.isUnderutilized {
                    Label("Low", systemImage: "arrow.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Text("\(pasture.activeAnimalCount) head")
                if pasture.acres > 0 {
                    Text("• \(pasture.acres.formatted(.number.precision(.fractionLength(0...1)))) ac")
                }
                if let capacity = pasture.capacityHead {
                    Text("• cap \(Int(capacity))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let capacity = pasture.capacityHead, capacity > 0 {
                ProgressView(value: Double(pasture.activeAnimalCount), total: capacity)
            }
        }
    }
}
