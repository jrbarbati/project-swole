import SwiftUI
import SwiftData
import SwoleData

struct ExerciseDetailSheet: View {
    let log: ExerciseLog
    let config: UserExerciseConfig?
    let unit: MeasurementUnit

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var completedWarmups: Set<Int> = []
    @State private var note: String = ""
    @State private var history: [ExerciseLog] = []

    private var warmups: [WarmupSet] {
        WarmupPlanner.plan(
            workingWeight: log.targetWeight,
            barWeight: PlateCalculator.barWeight(for: unit),
            increment: config?.weightIncrement ?? 5
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(log.exercise?.name ?? "")
                    .font(Theme.Font.display(26))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(log.targetWeight.formatted()) \(unit.rawValue.uppercased())")
                    .font(Theme.Font.numeric(15))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.top, 20)

            if !warmups.isEmpty {
                section("Warmup") {
                    VStack(spacing: 7) {
                        ForEach(warmups) { warmup in
                            Button {
                                toggle(warmup.id)
                            } label: {
                                HStack {
                                    Text("\(warmup.weight.formatted()) \(unit.rawValue.uppercased()) × \(warmup.reps)")
                                        .font(Theme.Font.numeric(14))
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(completedWarmups.contains(warmup.id) ? Theme.accent.opacity(0.2) : Theme.surface)
                                        .frame(width: 26, height: 26)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(completedWarmups.contains(warmup.id) ? Theme.accentStroke : Theme.borderStrong,
                                                        lineWidth: 1)
                                        )
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 14)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            section("Last \(history.count) sessions", trailing: trendLabel) {
                WeightTrendChart(logs: history, currentWeight: log.targetWeight)
                    .frame(height: 104)
            }

            section("Note") {
                TextField("Anything worth remembering", text: $note, axis: .vertical)
                    .font(Theme.Font.body(14))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Text("Edit weight")
                        .font(Theme.Font.body(15))
                        .foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .stroke(Theme.borderStrong, lineWidth: 1)
                        )
                }
                Button {
                    save()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.canvas)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .background(Theme.canvas)
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    private var trendLabel: String? {
        guard let earliest = history.first?.targetWeight else { return nil }
        let delta = log.targetWeight - earliest
        guard delta != 0 else { return nil }
        return "\(delta > 0 ? "+" : "")\(delta.formatted()) \(unit.rawValue.uppercased())"
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel(text: title).tracking(1.6)
                if let trailing {
                    Spacer()
                    MetaLabel(text: trailing, color: Theme.accentText)
                }
            }
            content()
        }
        .padding(.top, 24)
    }

    private func toggle(_ id: Int) {
        if completedWarmups.contains(id) { completedWarmups.remove(id) } else { completedWarmups.insert(id) }
    }

    @MainActor
    private func load() async {
        guard let exercise = log.exercise else { return }
        history = (try? ProgressionCalculator.recentLogs(for: exercise, limit: 8, in: modelContext)) ?? []
        note = log.note ?? ""
    }

    private func save() {
        log.note = note.isEmpty ? nil : note
        try? modelContext.save()
    }
}

// MARK: - Trend chart
//
// Bars, not a line: the working weight is a step function and the misses are
// the story. Red bar = the session was failed at that weight.

struct WeightTrendChart: View {
    let logs: [ExerciseLog]
    let currentWeight: Double

    private var maxWeight: Double {
        max(currentWeight, logs.map(\.targetWeight).max() ?? currentWeight, 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(logs) { entry in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(entry.succeeded ? Theme.borderStrong : Theme.missStroke)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(8, 104 * entry.targetWeight / maxWeight))
                }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(8, 104 * currentWeight / maxWeight))
            }
            HStack {
                MetaLabel(text: (logs.first?.targetWeight ?? currentWeight).formatted(), color: Theme.textDim)
                Spacer()
                MetaLabel(text: "\(currentWeight.formatted()) today", color: Theme.textDim)
            }
        }
    }
}
