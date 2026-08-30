import SwiftUI
import SwiftData
import SwoleData

struct SessionDetailView: View {
    let session: WorkoutSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var configs: [UserExerciseConfig]
    @Query private var settingsList: [UserSettings]

    private var unit: MeasurementUnit { settingsList.first?.unit ?? .lb }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 14)

                loggedExercises
                    .padding(.top, 26)

                repeatButton
                    .padding(.top, 20)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Workout \(session.workoutType.rawValue)")
                    .font(Theme.Font.display(34))
                    .foregroundStyle(Theme.textPrimary)
                MetaLabel(text: session.startedAt.formatted(.dateTime.month(.abbreviated).day()),
                          color: Theme.textDim)
            }
            HStack(spacing: 18) {
                MetaLabel(text: durationText)
                MetaLabel(text: "\(unit.fromLb(session.volume).formatted(.number.precision(.fractionLength(0)))) \(unit.rawValue)")
                MetaLabel(text: "\(session.loggedSetCount)/\(session.totalSetCount) sets")
            }
        }
    }

    private var loggedExercises: some View {
        VStack(spacing: 12) {
            ForEach(session.sortedLogs) { log in
                LoggedExerciseCard(log: log, unit: unit, warning: deloadWarning(for: log))
            }

            if let note = session.note, !note.isEmpty {
                noteCard(note)
            }
        }
    }

    private func noteCard(_ note: String) -> some View {
        Text(note)
            .font(Theme.Font.body(14))
            .foregroundStyle(Theme.textSecondary)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, Theme.Space.cardPadding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }

    private var repeatButton: some View {
        Button {
            // Starting from history uses the same service call as Today —
            // the schedule decides the type, so this is just a shortcut.
            _ = try? WorkoutSessionService.startWorkout(in: modelContext)
            dismiss()
        } label: {
            Text("Repeat this workout")
                .font(Theme.Font.body(15))
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .stroke(Theme.borderStrong, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var durationText: String {
        guard let finishedAt = session.finishedAt else { return "—" }
        let seconds = Int(finishedAt.timeIntervalSince(session.startedAt))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// "2ND MISS AT 110 · ONE MORE TRIGGERS DELOAD"
    private func deloadWarning(for log: ExerciseLog) -> String? {
        guard !log.succeeded,
              let exercise = log.exercise,
              let config = configs.first(where: { $0.exercise?.persistentModelID == exercise.persistentModelID }),
              let streak = try? ProgressionCalculator.currentFailStreak(for: exercise, in: modelContext),
              streak > 0
        else { return nil }

        let ordinal = "\(streak)\(streak.ordinalSuffix)"

        let remaining = config.deloadThreshold - streak
        let displayWeight = unit.fromLb(log.targetWeight).formattedWeight
        if remaining <= 0 {
            return "\(ordinal) miss at \(displayWeight) · deload applied"
        }
        return "\(ordinal) miss at \(displayWeight) · \(remaining) more triggers deload"
    }
}

// MARK: - Read-only exercise card

private struct LoggedExerciseCard: View {
    let log: ExerciseLog
    let unit: MeasurementUnit
    let warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(log.exercise?.name ?? "")
                    .font(Theme.Font.title(18))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(unit.fromLb(log.targetWeight).formattedWeight) \(unit.rawValue.uppercased())")
                    .font(Theme.Font.numeric(14))
                    .foregroundStyle(Theme.textMuted)
            }

            // Shorter than the interactive tiles (46pt) — nothing here is tappable.
            HStack(spacing: Theme.Space.tileGap) {
                ForEach(log.sortedSets) { set in
                    repsTile(reps: set.repsCompleted ?? 0)
                }
            }

            if let warning {
                MetaLabel(text: warning, color: Theme.textDim).tracking(1.2)
            }
        }
        .padding(Theme.Space.cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func repsTile(reps: Int) -> some View {
        Text("\(reps)")
            .font(Theme.Font.numeric(18))
            .foregroundStyle(textColor(forReps: reps))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                fill(forReps: reps),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
    }

    private func textColor(forReps reps: Int) -> Color {
        if reps >= log.targetReps { return Theme.accentText }
        if reps == 0 { return Theme.textFaint }
        return Theme.miss
    }

    private func fill(forReps reps: Int) -> Color {
        if reps >= log.targetReps { return Theme.accent.opacity(0.14) }
        if reps == 0 { return Theme.surfaceSunken }
        return Theme.missFill
    }
}
