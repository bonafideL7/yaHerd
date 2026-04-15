//
//  AnimalListControlBars.swift
//

import SwiftUI

struct AnimalListFloatingControlBar: View {
    @Binding var isSearching: Bool
    @Binding var searchText: String
    @Binding var sortOrder: AnimalSortOrder
    let filtersAreActive: Bool
    let filterChipCount: Int
    let hasAnyActiveCriteria: Bool
    let chips: [AnimalListFilterChip]
    let onShowFilters: () -> Void
    let onClearAllCriteria: () -> Void
    @FocusState.Binding var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if isSearching {
                    AnimalListBottomSearchField(
                        searchText: $searchText,
                        isSearchFieldFocused: $isSearchFieldFocused
                    )

                    Button("Cancel") {
                        searchText = ""
                        isSearchFieldFocused = false
                        withAnimation(.snappy) {
                            isSearching = false
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .buttonStyle(.plain)
                } else {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(AnimalSortOrder.allCases, id: \.self) { option in
                                Label(option.label, systemImage: option.icon)
                                    .tag(option)
                            }
                        }
                    } label: {
                        AnimalListFloatingControlLabel(
                            title: sortOrder.label,
                            systemImage: "arrow.up.arrow.down"
                        )
                    }

                    Button(action: onShowFilters) {
                        AnimalListFloatingControlLabel(
                            title: filtersAreActive ? "Filters On" : "Filters",
                            systemImage: filtersAreActive
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.snappy) {
                            isSearching = true
                        }
                    } label: {
                        AnimalListFloatingIconControlLabel(systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.plain)
                }
            }

            if !isSearching && !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if hasAnyActiveCriteria {
                            Button("Clear", action: onClearAllCriteria)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.thinMaterial, in: Capsule())
                                .buttonStyle(.plain)
                        }

                        if !chips.isEmpty {
                            Text("\(filterChipCount) active filter\(filterChipCount == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 4)
                        }

                        ForEach(chips) { chip in
                            Button(action: chip.remove) {
                                HStack(spacing: 6) {
                                    Text(chip.title)
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(.thinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .shadow(radius: 10, y: 4)
        .onChange(of: isSearching) { _, newValue in
            if newValue { isSearchFieldFocused = true }
        }
    }
}

struct AnimalListFloatingIconControlLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.medium))
            .frame(width: 44, height: 44)
            .background(.thinMaterial, in: Capsule())
    }
}

struct AnimalListFloatingControlLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: Capsule())
    }
}

struct AnimalListBottomSearchField: View {
    @Binding var searchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search tag, color, or name", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .focused($isSearchFieldFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: Capsule())
    }
}

struct AnimalListBatchActionBar: View {
    let selectedCount: Int
    let allVisibleAnimalsSelected: Bool
    let onToggleSelectAllVisible: () -> Void
    let onMove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedCount == 0 ? "Selection Mode" : "\(selectedCount) Selected")
                    .font(.caption)

                Button(allVisibleAnimalsSelected ? "Deselect All" : "Select All") {
                    onToggleSelectAllVisible()
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.automatic)
            }

            Spacer()

            Button(action: onMove) {
                Label("Move", systemImage: "arrowshape.turn.up.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCount == 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .shadow(radius: 10, y: 4)
    }
}

struct AnimalListFilterChip: Identifiable {
    let id = UUID()
    let title: String
    let remove: () -> Void
}
