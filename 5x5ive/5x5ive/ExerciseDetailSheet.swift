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
            header

            if !warmups.isEmpty {
                warmupSection
            }

            trendSection
            noteSection

            Spacer(minLength: 12)

            actionRow
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .background(Theme.canvas)
        .presentationDragIndicator(.visible)
        .task { await loadHistory() }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(log.exercise?.name ?? "")
                .font(Theme.Font.display(26))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            weightStepper
        }
        .padding(.top, 20)
    }

    /// Edits `log.targetWeight` directly — this only ever affects the
    /// exercise log of the session already in progress, since this sheet is
    /// only ever presented from `ActiveWorkoutView`.
    private var weightStepper: some View {
        HStack(spacing: 10) {
            StepButton(symbol: "−") {
                log.targetWeight = max(0, log.targetWeight - (config?.weightIncrement ?? 5))
                try? modelContext.save()
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(log.targetWeight.formatted(.number.precision(.fractionLength(0...1))))
                    .font(Theme.Font.numeric(15))
                    .foregroundStyle(Theme.textMuted)
                Text(unit.rawValue.uppercased())
                    .font(Theme.Font.numeric(15))
                    .foregroundStyle(Theme.textMuted)
            }
            StepButton(symbol: "+") {
                log.targetWeight += (config?.weightIncrement ?? 5)
                try? modelContext.save()
            }
        }
    }

    private var warmupSection: some View {
        section("Warmup") {
            VStack(spacing: 7) {
                ForEach(warmups) { warmup in
                    warmupRow(warmup)
                }
            }
        }
    }

    private func warmupRow(_ warmup: WarmupSet) -> some View {
        let isDone = completedWarmups.contains(warmup.id)
        return Button {
            toggleWarmup(warmup.id)
        } label: {
            HStack {
                Text("\(warmup.weight.formatted()) \(unit.rawValue.uppercased()) × \(warmup.reps)")
                    .font(Theme.Font.numeric(14))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDone ? Theme.accent.opacity(0.2) : Theme.surface)
                    .frame(width: 26, height: 26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isDone ? Theme.accentStroke : Theme.borderStrong, lineWidth: 1)
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

    private var trendSection: some View {
        section("Last \(history.count) sessions", trailing: trendLabel) {
            WeightTrendChart(logs: history, currentWeight: log.targetWeight)
                .frame(height: 104)
        }
    }

    private var noteSection: some View {
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
    }

    private var actionRow: some View {
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

    // MARK: Actions

    private func toggleWarmup(_ id: Int) {
        if completedWarmups.contains(id) {
            completedWarmups.remove(id)
        } else {
            completedWarmups.insert(id)
        }
    }

    @MainActor
    private func loadHistory() async {
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

    private let maxBarHeight: Double = 104

    private var maxWeight: Double {
        max(currentWeight, logs.map(\.targetWeight).max() ?? currentWeight, 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(logs) { entry in
                    bar(weight: entry.targetWeight, color: entry.succeeded ? Theme.borderStrong : Theme.missStroke)
                }
                bar(weight: currentWeight, color: Theme.accent)
            }
            HStack {
                MetaLabel(text: (logs.first?.targetWeight ?? currentWeight).formatted(), color: Theme.textDim)
                Spacer()
                MetaLabel(text: "\(currentWeight.formatted()) today", color: Theme.textDim)
            }
        }
    }

    private func bar(weight: Double, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color)
            .frame(maxWidth: .infinity)
            .frame(height: max(8, maxBarHeight * weight / maxWeight))
    }
}
