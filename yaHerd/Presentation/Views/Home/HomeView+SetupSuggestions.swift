import SwiftUI

extension HomeView {
    @ViewBuilder
    var setupSuggestionsSection: some View {
        if hasSetupSuggestionRows {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.snappy) {
                        isSetupSuggestionsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Setup Suggestions")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.primary)

                            Text(setupSuggestionsSummaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        Image(systemName: isSetupSuggestionsExpanded ? "chevron.up" : "chevron.down")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .modifier(HomeGlassControlBackground(cornerRadius: 17, tint: .accentColor))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(RoundedRectangle(cornerRadius: HomeSuggestionLayout.sectionCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Setup Suggestions")
                .accessibilityValue(isSetupSuggestionsExpanded ? "Expanded, \(setupSuggestionsSummaryText)" : "Collapsed, \(setupSuggestionsSummaryText)")
                .accessibilityHint(isSetupSuggestionsExpanded ? "Double tap to collapse" : "Double tap to expand")

                if isSetupSuggestionsExpanded {
                    setupSuggestionsCarousel
                        .padding(.top, 2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.bottom, isSetupSuggestionsExpanded ? 8 : 0)
            .modifier(HomeGlassCardBackground(cornerRadius: HomeSuggestionLayout.sectionCornerRadius, tint: .accentColor))
            .clipShape(RoundedRectangle(cornerRadius: HomeSuggestionLayout.sectionCornerRadius, style: .continuous))
        }
    }

    var setupSuggestionsCarousel: some View {
        GeometryReader { proxy in
            let cardWidth = HomeSuggestionLayout.cardWidth(for: proxy.size.width)

            GlassEffectContainer(spacing: HomeSuggestionLayout.cardSpacing) {
                setupSuggestionsPeekCarousel(cardWidth: cardWidth)
            }
        }
        .frame(height: HomeSuggestionLayout.carouselHeight)
    }

    func setupSuggestionsPeekCarousel(cardWidth: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: HomeSuggestionLayout.cardSpacing) {
                ForEach(visibleSetupSuggestionIDs, id: \.self) { id in
                    setupSuggestionRow(for: id, cardWidth: cardWidth)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, HomeSuggestionLayout.carouselHorizontalPadding, for: .scrollContent)
        .contentMargins(.vertical, HomeSuggestionLayout.carouselVerticalPadding, for: .scrollContent)
        .accessibilityHint(Text(visibleSetupSuggestionIDs.count > 1 ? "Swipe left or right for more setup suggestions." : ""))
    }

    var setupSuggestionsSummaryText: String {
        let count = visibleSetupSuggestionIDs.count
        return count == 1 ? "1 setup item" : "\(count) setup items"
    }

    @ViewBuilder
    func setupSuggestionRow(for id: HomeSetupSuggestionID, cardWidth: CGFloat) -> some View {
        switch id {
        case .addFirstPasture:
            HomeSuggestionButtonRow(
                title: "Add your first pasture",
                subtitle: "Pasture checks, stocking status, and rotation work need at least one pasture.",
                systemImage: "leaf.fill",
                tint: .green,
                actionTitle: "Add",
                cardWidth: cardWidth,
                onAction: { isPresentingAddPasture = true },
                onDismiss: { dismissSetupSuggestion(.addFirstPasture) }
            )
        case .addFirstAnimal:
            HomeSuggestionButtonRow(
                title: "Add your first animal",
                subtitle: "Create the first herd record so field checks and working sessions have something to use.",
                systemImage: "tag.fill",
                tint: .blue,
                actionTitle: "Add",
                cardWidth: cardWidth,
                onAction: { isPresentingAddAnimal = true },
                onDismiss: { dismissSetupSuggestion(.addFirstAnimal) }
            )
        case .startFirstPastureCheck:
            HomeSuggestionButtonRow(
                title: "Start your first pasture check",
                subtitle: "Build check history for pasture rosters, missing animals, and field findings.",
                systemImage: "checklist",
                tint: .purple,
                actionTitle: "Start",
                cardWidth: cardWidth,
                onAction: { isStartingFieldCheck = true },
                onDismiss: { dismissSetupSuggestion(.startFirstPastureCheck) }
            )
        case .createWorkingProtocol:
            HomeSuggestionNavigationRow(
                title: "Create a working protocol",
                subtitle: "Set up reusable treatment or processing steps before the first working session.",
                systemImage: "list.clipboard.fill",
                tint: .orange,
                actionTitle: "Open",
                cardWidth: cardWidth,
                destination: { ProtocolTemplatesView() },
                onDismiss: { dismissSetupSuggestion(.createWorkingProtocol) }
            )
        case .enableDashboard:
            HomeSuggestionNavigationRow(
                title: "Enable the Dashboard tab",
                subtitle: "Turn on herd-level summaries when you want a status screen separate from Home.",
                systemImage: "rectangle.3.group.fill",
                tint: .blue,
                actionTitle: "Open",
                cardWidth: cardWidth,
                destination: { DashboardRulesView() },
                onDismiss: { dismissSetupSuggestion(.enableDashboard) }
            )
        case .customizeTagColors:
            HomeSuggestionNavigationRow(
                title: "Customize tag colors",
                subtitle: "Add ranch-specific colors or prefixes for faster field identification.",
                systemImage: "tag.fill",
                tint: .yellow,
                actionTitle: "Open",
                cardWidth: cardWidth,
                destination: { TagColorLibraryView() },
                onDismiss: { dismissSetupSuggestion(.customizeTagColors) }
            )
        case .completePastureStockingData:
            HomeSuggestionButtonRow(
                title: "Complete pasture stocking data",
                subtitle: "Add acreage and target acres/head so capacity and rotation guidance is useful.",
                systemImage: "ruler.fill",
                tint: .brown,
                actionTitle: "Open",
                cardWidth: cardWidth,
                onAction: { openPastureList(.missingStockingData) },
                onDismiss: { dismissSetupSuggestion(.completePastureStockingData) }
            )
        case .reviewSyncSetup:
            HomeSuggestionNavigationRow(
                title: "Set up sync",
                subtitle: "Data is currently stored on this device only.",
                systemImage: "icloud.slash.fill",
                tint: .cyan,
                actionTitle: "Open",
                cardWidth: cardWidth,
                destination: { SyncSettingsView() },
                onDismiss: { dismissSetupSuggestion(.reviewSyncSetup) }
            )
        }
    }
}
