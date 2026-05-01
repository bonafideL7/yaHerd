//
//  HierarchicalIncrementCounterPreview.swift
//  yaHerd
//
//  Created by mm on 4/30/26.
//

import SwiftUI

struct CounterBucket<ID: Hashable>: Identifiable, Hashable {
    let id: ID
    let name: String
    let total: Int
}

struct HierarchicalIncrementCounter<ID: Hashable>: View {
    let title: String
    let total: Int
    let buckets: [CounterBucket<ID>]

    @Binding var allCount: Int
    @Binding var bucketCounts: [ID: Int]

    @State private var selectedBucketID: ID?
    @State private var isLargeTapTargetPresented = false

    private var selectedBucket: CounterBucket<ID>? {
        guard let selectedBucketID else { return nil }
        return buckets.first { $0.id == selectedBucketID }
    }

    private var activeTitle: String {
        selectedBucket?.name ?? title
    }

    private var activeTotal: Int {
        selectedBucket?.total ?? total
    }

    private var activeCount: Int {
        if let selectedBucketID {
            return min(max(bucketCounts[selectedBucketID, default: 0], 0), activeTotal)
        }
        return min(max(allCount, 0), activeTotal)
    }

    private var isComplete: Bool {
        activeTotal > 0 && activeCount >= activeTotal
    }

    var body: some View {
        HStack(spacing: 10) {
            scopeSelector

            Spacer(minLength: 8)

            countDisplay

            Button {
                decrement()
            } label: {
                Image(systemName: "minus")
                    .font(.headline)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .disabled(activeCount == 0)

            Button {
                increment()
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderedProminent)
            .disabled(activeTotal == 0 || isComplete)

            Button {
                confirmTotal()
            } label: {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.title3)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isComplete ? .green : .secondary)
            .disabled(activeTotal == 0)
            .accessibilityLabel("Confirm all counted")

            Button {
                isLargeTapTargetPresented = true
            } label: {
                Image(systemName: "hand.tap")
                    .font(.title3)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(activeTotal == 0)
            .accessibilityLabel("Open large tap target")
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sheet(isPresented: $isLargeTapTargetPresented) {
            LargeCounterTapTarget(
                title: activeTitle,
                count: activeCount,
                total: activeTotal,
                increment: increment,
                confirmTotal: confirmTotal
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var scopeSelector: some View {
        Menu {
            Button {
                selectedBucketID = nil
            } label: {
                Label(title, systemImage: selectedBucketID == nil ? "checkmark" : "circle")
            }

            if !buckets.isEmpty {
                Divider()
            }

            ForEach(buckets) { bucket in
                Button {
                    selectedBucketID = bucket.id
                } label: {
                    Label(
                        "\(bucket.name) \(bucketCounts[bucket.id, default: 0])/\(bucket.total)",
                        systemImage: selectedBucketID == bucket.id ? "checkmark" : "circle"
                    )
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(activeTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 150, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var countDisplay: some View {
        Text("\(activeCount)/\(activeTotal)")
            .font(.system(.headline, design: .rounded).monospacedDigit())
            .contentTransition(.numericText())
            .frame(minWidth: 58, alignment: .trailing)
            .accessibilityLabel("\(activeCount) of \(activeTotal)")
    }

    private func increment() {
        guard activeCount < activeTotal else { return }
        setActiveCount(activeCount + 1)
    }

    private func decrement() {
        guard activeCount > 0 else { return }
        setActiveCount(activeCount - 1)
    }

    private func confirmTotal() {
        setActiveCount(activeTotal)
    }

    private func setActiveCount(_ newValue: Int) {
        let clampedValue = min(max(newValue, 0), activeTotal)

        if let selectedBucketID {
            bucketCounts[selectedBucketID] = clampedValue
        } else {
            allCount = clampedValue
        }
    }
}

struct FieldCheckAnimalQuickCountCounter: View {
    let remainingRosterChecks: [FieldCheckAnimalCheckSnapshot]
    @Binding var animalTypeCounts: [AnimalType: Int]

    private var buckets: [CounterBucket<AnimalType>] {
        let counts = Dictionary(grouping: remainingRosterChecks, by: \FieldCheckAnimalCheckSnapshot.animalType)
            .mapValues(\.count)

        return AnimalType.allCases.compactMap { animalType in
            let total = counts[animalType, default: 0]
            guard total > 0 else { return nil }
            return CounterBucket(id: animalType, name: animalType.label, total: total)
        }
    }

    private var total: Int {
        remainingRosterChecks.count
    }

    private var totalQuickCount: Int {
        buckets.reduce(0) { partialResult, bucket in
            partialResult + min(max(animalTypeCounts[bucket.id, default: 0], 0), bucket.total)
        }
    }

    var body: some View {
        HierarchicalIncrementCounter(
            title: "Roster Count",
            total: total,
            buckets: buckets,
            allCount: Binding(
                get: { totalQuickCount },
                set: applyTotalQuickCount
            ),
            bucketCounts: $animalTypeCounts
        )
    }

    private func applyTotalQuickCount(_ newValue: Int) {
        let target = min(max(newValue, 0), total)
        var counts = normalizedAnimalTypeCounts()
        let current = counts.values.reduce(0, +)

        if target > current {
            var remainingIncrease = target - current
            for bucket in buckets where remainingIncrease > 0 {
                let currentBucketCount = counts[bucket.id, default: 0]
                let available = max(bucket.total - currentBucketCount, 0)
                let increase = min(available, remainingIncrease)
                counts[bucket.id] = currentBucketCount + increase
                remainingIncrease -= increase
            }
        } else if target < current {
            var remainingDecrease = current - target
            for bucket in buckets.reversed() where remainingDecrease > 0 {
                let currentBucketCount = counts[bucket.id, default: 0]
                let decrease = min(currentBucketCount, remainingDecrease)
                counts[bucket.id] = currentBucketCount - decrease
                remainingDecrease -= decrease
            }
        }

        animalTypeCounts = counts.filter { $0.value > 0 }
    }

    private func normalizedAnimalTypeCounts() -> [AnimalType: Int] {
        var normalized: [AnimalType: Int] = [:]
        for bucket in buckets {
            normalized[bucket.id] = min(max(animalTypeCounts[bucket.id, default: 0], 0), bucket.total)
        }
        return normalized
    }
}

private struct LargeCounterTapTarget: View {
    let title: String
    let count: Int
    let total: Int
    let increment: () -> Void
    let confirmTotal: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var isComplete: Bool {
        total > 0 && count >= total
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text("\(count) of \(total)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            Button {
                increment()
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: isComplete ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 72))

                    Text(isComplete ? "Complete" : "Tap Anywhere to Count")
                        .font(.title3.weight(.semibold))

                    Text(isComplete ? "All animals counted" : "Large target mode")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isComplete || total == 0)

            Button {
                confirmTotal()
            } label: {
                Label("Confirm Total", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isComplete || total == 0)
        }
        .padding()
    }
}

struct HierarchicalIncrementCounterDemoStruct4: View {
    private enum DemoBucket: String, CaseIterable {
        case cows
        case calves
        case bulls
        case heifers

        var label: String {
            switch self {
            case .cows: return "Cows"
            case .calves: return "Calves"
            case .bulls: return "Bulls"
            case .heifers: return "Heifers"
            }
        }

        var total: Int {
            switch self {
            case .cows: return 18
            case .calves: return 11
            case .bulls: return 2
            case .heifers: return 7
            }
        }
    }

    private let buckets = DemoBucket.allCases.map {
        CounterBucket(id: $0, name: $0.label, total: $0.total)
    }

    @State private var allCount = 0
    @State private var bucketCounts: [DemoBucket: Int] = [:]

    private var total: Int {
        buckets.reduce(0) { $0 + $1.total }
    }

    private var bucketTotalCount: Int {
        buckets.reduce(0) { partialResult, bucket in
            partialResult + min(max(bucketCounts[bucket.id, default: 0], 0), bucket.total)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Counter") {
                    HierarchicalIncrementCounter(
                        title: "All Items",
                        total: total,
                        buckets: buckets,
                        allCount: $allCount,
                        bucketCounts: $bucketCounts
                    )
                }

                Section("Debug State") {
                    LabeledContent("All Items", value: "\(allCount)/\(total)")
                    LabeledContent("Bucket Total", value: "\(bucketTotalCount)/\(total)")

                    ForEach(buckets) { bucket in
                        LabeledContent(
                            bucket.name,
                            value: "\(bucketCounts[bucket.id, default: 0])/\(bucket.total)"
                        )
                    }
                }
            }
            .navigationTitle("Counter Control")
        }
    }
}

#Preview("Generic Counter") {
    HierarchicalIncrementCounterDemoStruct4()
}
