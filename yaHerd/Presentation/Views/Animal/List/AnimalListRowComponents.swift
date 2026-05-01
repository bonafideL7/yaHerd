//
//  AnimalListRowComponents.swift
//

import SwiftUI

struct AnimalListRowContent: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let animal: AnimalSummary

    var body: some View {
        let def = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)
        let damDef = tagColorLibrary.resolvedDefinition(tagColorID: animal.damDisplayTagColorID)

        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                AnimalTagView(
                    tagNumber: animal.displayTagNumber,
                    color: def.color,
                    colorName: def.name,
                    damTagNumber: animal.damDisplayTagNumber,
                    damTagColor: damDef.color,
                    damTagColorName: damDef.name,
                    damTagVisibility: animal.animalType == .calf ? .always : .whenUntagged
                )

                if !animal.name.isEmpty {
                    AnimalListInfoPill(title: animal.name, systemImage: "")
                } else {
                    AnimalListTypeAndFeaturePill(animal: animal)
                }
            }

            VStack(alignment: .trailing, spacing: 8) {
                if animal.status != .active || animal.isArchived {
                    AnimalListStatusPills(animal: animal)
                } else {
                    AnimalListLocationBadges(animal: animal)
                }

                AnimalListAgeAndBirthDatePills(animal: animal)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct AnimalListTypeAndFeaturePill: View {
    let animal: AnimalSummary

    var body: some View {
        HStack(spacing: 4) {
            Text(animal.animalType.label)
                .font(.callout)
                .foregroundStyle(Color.accentColor)

            if let feature = animal.firstDistinguishingFeature, !feature.isEmpty {
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(feature)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }
}

struct AnimalListAgeAndBirthDatePills: View {
    let animal: AnimalSummary

    private var birthDateText: String {
        animal.birthDate.formatted(.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits))
    }

    private var compactBirthDateText: String {
        animal.birthDate.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            AnimalListCombinedAgeBirthDatePill(
                ageText: animal.age,
                birthDateText: birthDateText
            )

            AnimalListCombinedAgeBirthDatePill(
                ageText: animal.age,
                birthDateText: compactBirthDateText
            )

            AnimalListInfoPill(title: animal.age, systemImage: "calendar")
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct AnimalListCombinedAgeBirthDatePill: View {
    let ageText: String
    let birthDateText: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar")

            Text(ageText)

            Text("•")
                .font(.caption2)

            Text(birthDateText)
        }
        .font(.callout)
        .foregroundStyle(.fill)
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }
}

struct AnimalListInfoPill: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 3) {
            if !systemImage.isEmpty {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.callout)
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }
}

struct AnimalListStatusPills: View {
    let animal: AnimalSummary

    var body: some View {
        HStack(spacing: 6) {
            if animal.status != .active {
                AnimalListInfoPill(
                    title: animal.status.label,
                    systemImage: animal.status.systemImage,
                    tint: .secondary
                )
            }

            if animal.isArchived {
                AnimalListInfoPill(
                    title: "Archived",
                    systemImage: "archivebox",
                    tint: .orange
                )
            }
        }
    }
}

struct AnimalListLocationBadges: View {
    let animal: AnimalSummary

    var body: some View {
        if animal.location == .workingPen {
            AnimalListPastureBadge(
                title: "Working Pen",
                systemImage: "figure.corral",
                tint: .orange,
                fillOpacity: 0.14
            )
        } else if let pastureName = animal.pastureName {
            AnimalListPastureBadge(
                title: pastureName,
                systemImage: "leaf",
                tint: .accent,
                fillOpacity: 0.12
            )
        } else {
            Spacer()
        }
    }
}

struct AnimalListPastureBadge: View {
    let title: String
    let systemImage: String
    let tint: Color
    let fillOpacity: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(Capsule().fill(tint.opacity(fillOpacity)))
    }
}
