//
//  AnimalListTabAccessoryControls.swift
//

import SwiftUI

struct AnimalListAdaptiveTabAccessoryControls: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    @Binding var sortOrder: AnimalSortOrder
    let filtersAreActive: Bool
    let activeFilterCount: Int
    let hasAnyActiveCriteria: Bool
    let onShowFilters: () -> Void
    let onClearAllCriteria: () -> Void

    var body: some View {
        if case .some(.inline) = placement {
            AnimalListInlineTabAccessoryControls(
                sortOrder: $sortOrder,
                filtersAreActive: filtersAreActive,
                activeFilterCount: activeFilterCount,
                hasAnyActiveCriteria: hasAnyActiveCriteria,
                onShowFilters: onShowFilters,
                onClearAllCriteria: onClearAllCriteria
            )
        } else {
            AnimalListTabAccessoryControls(
                sortOrder: $sortOrder,
                filtersAreActive: filtersAreActive,
                activeFilterCount: activeFilterCount,
                hasAnyActiveCriteria: hasAnyActiveCriteria,
                onShowFilters: onShowFilters,
                onClearAllCriteria: onClearAllCriteria
            )
        }
    }
}

struct AnimalListInlineTabAccessoryControls: View {
    @Binding var sortOrder: AnimalSortOrder
    let filtersAreActive: Bool
    let activeFilterCount: Int
    let hasAnyActiveCriteria: Bool
    let onShowFilters: () -> Void
    let onClearAllCriteria: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                AnimalSortMenuPicker(sortOrder: $sortOrder)
            } label: {
                AnimalListInlineTabAccessoryActionLabel(
                    title: sortOrder.label,
                    compactTitle: "Sort",
                    systemImage: "arrow.up.arrow.down"
                )
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 24)

            Button(action: onShowFilters) {
                AnimalListInlineTabAccessoryActionLabel(
                    title: filterDetail,
                    compactTitle: "Filter",
                    systemImage: filtersAreActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
                )
            }
            .buttonStyle(.plain)

            if hasAnyActiveCriteria {
                Divider()
                    .frame(height: 24)
                    .transition(.opacity)

                Button(action: onClearAllCriteria) {
                    AnimalListInlineTabAccessoryActionLabel(
                        title: "Clear",
                        compactTitle: "Clear",
                        systemImage: "xmark.circle.fill"
                    )
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .font(.footnote.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: hasAnyActiveCriteria)
        .accessibilityElement(children: .contain)
    }

    private var filterDetail: String {
        if filtersAreActive {
            return "\(max(activeFilterCount, 1)) active"
        }

        return "All"
    }
}

private struct AnimalListInlineTabAccessoryActionLabel: View {
    let title: String
    let compactTitle: String
    let systemImage: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)

            Label(compactTitle, systemImage: systemImage)
                .labelStyle(.titleAndIcon)

            Image(systemName: systemImage)
                .accessibilityLabel(title)
        }
        .contentShape(Rectangle())
    }
}

struct AnimalListTabAccessoryControls: View {
    @Binding var sortOrder: AnimalSortOrder
    let filtersAreActive: Bool
    let activeFilterCount: Int
    let hasAnyActiveCriteria: Bool
    let onShowFilters: () -> Void
    let onClearAllCriteria: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                AnimalSortMenuPicker(sortOrder: $sortOrder)
            } label: {
                AnimalListTabAccessoryActionLabel(
                    title: "Sort",
                    detail: sortOrder.label,
                    systemImage: "arrow.up.arrow.down"
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 32)

            Button(action: onShowFilters) {
                AnimalListTabAccessoryActionLabel(
                    title: "Filter",
                    detail: filterDetail,
                    systemImage: filtersAreActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasAnyActiveCriteria {
                Divider()
                    .frame(height: 32)
                    .transition(.opacity)

                Button(action: onClearAllCriteria) {
                    Label("Clear", systemImage: "xmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .labelStyle(.titleAndIcon)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Clear search and filters")
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: hasAnyActiveCriteria)
        .accessibilityElement(children: .contain)
    }

    private var filterDetail: String {
        if filtersAreActive {
            return "\(max(activeFilterCount, 1)) active"
        }

        return "All animals"
    }
}

private struct AnimalListTabAccessoryActionLabel: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(detail)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
