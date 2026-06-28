//
//  AnimalListFloatingControlBar.swift
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
    let showsSearchControl: Bool
    let usesExternalSearchField: Bool
    let onShowFilters: () -> Void
    let onClearAllCriteria: () -> Void
    @FocusState.Binding var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if isSearching && !usesExternalSearchField {
                    AnimalListBottomSearchField(
                        searchText: $searchText,
                        isSearchFieldFocused: $isSearchFieldFocused
                    )

                    ToolbarCancelButton {
                        searchText = ""
                        isSearchFieldFocused = false
                        withAnimation(.snappy) {
                            isSearching = false
                        }
                    }
                } else {
                    Menu {
                        AnimalSortMenuPicker(sortOrder: $sortOrder)
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

                    if showsSearchControl {
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
            }

            if (!isSearching || usesExternalSearchField) && hasAnyActiveCriteria {
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
            if newValue && !usesExternalSearchField { isSearchFieldFocused = true }
        }
    }
}


struct AnimalSortMenuPicker: View {
    @Binding var sortOrder: AnimalSortOrder

    var body: some View {
        Picker("Sort", selection: menuSelection) {
            ForEach(AnimalSortOrder.menuOptions, id: \.self) { option in
                Label(option.menuLabel, systemImage: option.menuIcon)
                    .tag(option)
            }
        }
    }

    private var menuSelection: Binding<AnimalSortOrder> {
        Binding {
            sortOrder.menuSelection
        } set: { newValue in
            sortOrder = newValue.defaultMenuSelection
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
