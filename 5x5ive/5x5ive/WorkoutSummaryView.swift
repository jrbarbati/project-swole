import SwiftUI
import SwiftData
import SwoleData

struct WorkoutSummaryView: View {
    let session: WorkoutSession
    let onSave: () -> Void
    let onBack: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var configs: [UserExerciseConfig]
    @Query private var settingsList: [UserSettings]

    @State private var note: String = ""

    private var unit: MeasurementUnit { settingsList.first?.unit ?? .lb }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                MetaLabel(text: "Workout \(session.workoutType.rawValue) complete", color: Theme.accentText)
                    .tracking(1.6)
                Text("\(session.loggedSetCount) of \(session.totalSetCount) sets logged")
                    .font(Theme.Font.display(40))
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(-2)
            }
            .padding(.top, 34)
            .padding(.horizontal, Theme.Space.screen)

            HStack(spacing: 10) {
                StatCard(label: "Duration", value: durationText)
                StatCard(label: "Volume", value: session.volume.formatted(.number.precision(.fractionLength(0))))
            }
            .padding(.top, 28)
            .padding(.horizontal, Theme.Space.screen)

            VStack(spacing: 9) {
                ForEach(session.sortedLogs) { log in
                    SummaryRow(log: log, outcome: outcome(for: log), unit: unit)
                }
                TextField("Add a session note", text: $note, axis: .vertical)
                    .font(Theme.Font.body(14))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, 14)
                    .padding(.horizontal, Theme.Space.cardPadding)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
                    .padding(.top, 6)
            }
            .padding(.top, 12)
            .padding(.horizontal, Theme.Space.screen)

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Button {
                    session.note = note.isEmpty ? nil : note
                    onSave()
                } label: {
                    Text("Save Workout")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.accentInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button("Back to workout", action: onBack)
                    .font(Theme.Font.body(15))
                    .foregroundStyle(Theme.textMuted)
                    .frame(height: 48)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, 12)
        }
        .background(Theme.canvas)
    }

    private var durationText: String {
        let seconds = Int(Date.now.timeIntervalSince(session.startedAt))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// What the program will do to this lift next session.
    private func outcome(for log: ExerciseLog) -> SummaryOutcome {
        guard let exercise = log.exercise,
              let config = configs.first(where: { $0.exercise?.persistentModelID == exercise.persistentModelID })
        else { return SummaryOutcome(headline: "—", detail: "", color: Theme.textMuted) }

        if log.succeeded {
            let next = log.targetWeight + config.weightIncrement
            return SummaryOutcome(
                headline: "Clear",
                detail: "Next \(next.formatted())",
                color: Theme.accentText
            )
        }

        // The miss just logged is not yet counted by currentFailStreak until the
        // session is saved, so add it here.
        let priorStreak = (try? ProgressionCalculator.currentFailStreak(for: exercise, in: modelContext)) ?? 0
        let streak = priorStreak + 1

        if streak >= config.deloadThreshold {
            let deloaded = (log.targetWeight * (1 - config.deloadPercentage) / config.weightIncrement)
                .rounded(.down) * config.weightIncrement
            return SummaryOutcome(
                headline: "\(streak)\(ordinalSuffix(streak)) miss",
                detail: "Deload \(deloaded.formatted())",
                color: Theme.warn
            )
        }

        return SummaryOutcome(
            headline: "Miss",
            detail: "Hold \(log.targetWeight.formatted())",
            color: Theme.miss
        )
    }

    private func ordinalSuffix(_ value: Int) -> String {
        switch value % 10 {
        case 1 where value % 100 != 11: "st"
        case 2 where value % 100 != 12: "nd"
        case 3 where value % 100 != 13: "rd"
        default: "th"
        }
    }
}

struct SummaryOutcome {
    let headline: String
    let detail: String
    let color: Color
}

private struct StatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetaLabel(text: label).tracking(1.3)
            Text(value)
                .font(Theme.Font.numeric(26))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

private struct SummaryRow: View {
    let log: ExerciseLog
    let outcome: SummaryOutcome
    let unit: MeasurementUnit

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(log.exercise?.name ?? "")
                    .font(Theme.Font.title(17))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(log.targetWeight.formatted()) · \(log.repsSummary)")
                    .font(Theme.Font.numeric(12))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(outcome.headline.uppercased())
                    .font(Theme.Font.label())
                    .foregroundStyle(outcome.color)
                Text(outcome.detail.uppercased())
                    .font(Theme.Font.label())
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, Theme.Space.cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}
