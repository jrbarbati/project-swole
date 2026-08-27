import SwiftUI
import SwiftData
import SwoleData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [UserSettings]
    @Query private var configs: [UserExerciseConfig]

    @AppStorage("appearance") private var appearance: String = "dark"
    @AppStorage("showWarmups") private var showWarmups: Bool = true

    private var settings: UserSettings? { settingsList.first }

    private var sortedConfigs: [UserExerciseConfig] {
        configs.sorted { ($0.exercise?.name ?? "") < ($1.exercise?.name ?? "") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(Theme.Font.display(34))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 14)

                workingWeightsSection
                restSection
                preferencesSection
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(appearance == "dark" ? .dark : .light)
    }

    private var workingWeightsSection: some View {
        SettingsSection(title: "Working weights") {
            VStack(spacing: 0) {
                ForEach(sortedConfigs) { config in
                    WeightRow(config: config, unit: settings?.unit ?? .lb) {
                        try? modelContext.save()
                    }
                }
            }
        }
    }

    private var restSection: some View {
        SettingsSection(title: "Rest") {
            HStack(spacing: 10) {
                RestCard(label: "After success",
                         seconds: sortedConfigs.first?.restSecondsOnSuccess ?? 90)
                RestCard(label: "After a miss",
                         seconds: sortedConfigs.first?.restSecondsOnFail ?? 180)
            }
        }
    }

    private var preferencesSection: some View {
        SettingsSection(title: "Preferences") {
            VStack(spacing: 0) {
                SettingRow(title: "Units") {
                    SegmentedPair(
                        options: ["LB", "KG"],
                        selection: (settings?.unit ?? .lb) == .lb ? "LB" : "KG"
                    ) { picked in
                        settings?.unit = picked == "LB" ? .lb : .kg
                        try? modelContext.save()
                    }
                }
                SettingRow(title: "Appearance") {
                    SegmentedPair(
                        options: ["DARK", "LIGHT"],
                        selection: appearance == "dark" ? "DARK" : "LIGHT"
                    ) { picked in
                        appearance = picked == "DARK" ? "dark" : "light"
                    }
                }
                SettingRow(title: "Deload after", subtitle: deloadSubtitle) {
                    Text("\(sortedConfigs.first?.deloadThreshold ?? 3) ›")
                        .font(Theme.Font.numeric(16))
                        .foregroundStyle(Theme.textMuted)
                }
                SettingRow(title: "Warmup sets", showsDivider: false) {
                    Toggle("", isOn: $showWarmups)
                        .labelsHidden()
                        .tint(Theme.accent)
                }
            }
        }
    }

    private var deloadSubtitle: String {
        let percentage = Int((sortedConfigs.first?.deloadPercentage ?? 0.1) * 100)
        return "Drop \(percentage)% after repeated misses"
    }
}

// MARK: - Pieces

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetaLabel(text: title).tracking(1.6)
            content
        }
    }
}

private struct WeightRow: View {
    let config: UserExerciseConfig
    let unit: MeasurementUnit
    let onChange: () -> Void

    @Environment(\.modelContext) private var modelContext

    /// The weight that will be used the next time this exercise's workout
    /// starts: the manual override if one is set, otherwise the same
    /// progression calculation the workout itself uses. Always live — no
    /// separate sync step needed after finishing a workout.
    private var currentWeight: Double {
        if let override = config.weightOverride { return override }
        guard let exercise = config.exercise else { return config.startingWeight }
        return (try? ProgressionCalculator.nextTargetWeight(for: exercise, config: config, in: modelContext))
            ?? config.startingWeight
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(config.exercise?.name ?? "")
                    .font(Theme.Font.title(16))
                    .foregroundStyle(Theme.textPrimary)
                MetaLabel(text: "+\(config.weightIncrement.formatted()) \(unit.rawValue) per session",
                          color: Theme.textDim)
                    .tracking(1.2)
            }
            Spacer()
            HStack(spacing: 10) {
                StepButton(symbol: "−") {
                    config.weightOverride = max(0, currentWeight - config.weightIncrement)
                    onChange()
                }
                Text(currentWeight.formatted(.number.precision(.fractionLength(0...1))))
                    .font(Theme.Font.numeric(19))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44)
                StepButton(symbol: "+") {
                    config.weightOverride = currentWeight + config.weightIncrement
                    onChange()
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

struct StepButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(Theme.Font.numeric(16))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 34, height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.borderStrong, lineWidth: 1)
                )
                // Visual box is 34pt; the hit area is padded to 44.
                .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(.plain)
    }
}

private struct RestCard: View {
    let label: String
    let seconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetaLabel(text: label, color: Theme.textDim).tracking(1.2)
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(Theme.Font.numeric(22))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, Theme.Space.cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

private struct SettingRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var showsDivider: Bool = true
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Font.body(16))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    MetaLabel(text: subtitle, color: Theme.textDim).tracking(1.2)
                }
            }
            Spacer()
            accessory
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }
}

/// Two-up pill switch, matching the mock rather than the stock segmented control.
private struct SegmentedPair: View {
    let options: [String]
    let selection: String
    let onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                Button {
                    onPick(option)
                } label: {
                    Text(option)
                        .font(Theme.Font.label(12).weight(option == selection ? .bold : .regular))
                        .foregroundStyle(option == selection ? Theme.canvas : Theme.textMuted)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(
                            option == selection ? Theme.textPrimary : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
