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
                        MetaLabel(text: "\(session.volume.formatted(.number.precision(.fractionLength(0)))) \(unit.rawValue)")
                        MetaLabel(text: "\(session.loggedSetCount)/\(session.totalSetCount) sets")
                    }
                }
                .padding(.top, 14)

                VStack(spacing: 12) {
                    ForEach(session.sortedLogs) { log in
                        LoggedExerciseCard(log: log, unit: unit, warning: deloadWarning(for: log))
                    }

                    if let note = session.note, !note.isEmpty {
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
                }
                .padding(.top, 26)

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
                .padding(.top, 20)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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

        let remaining = config.deloadThreshold - streak
        let ordinal = streak == 1 ? "1st" : streak == 2 ? "2nd" : "\(streak)th"
        if remaining <= 0 {
            return "\(ordinal) miss at \(log.targetWeight.formatted()) · deload applied"
        }
        return "\(ordinal) miss at \(log.targetWeight.formatted()) · \(remaining) more triggers deload"
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
                Text("\(log.targetWeight.formatted()) \(unit.rawValue.uppercased())")
                    .font(Theme.Font.numeric(14))
                    .foregroundStyle(Theme.textMuted)
            }

            // Shorter than the interactive tiles (46pt) — nothing here is tappable.
            HStack(spacing: Theme.Space.tileGap) {
                ForEach(log.sortedSets) { set in
                    let reps = set.repsCompleted ?? 0
                    Text("\(reps)")
                        .font(Theme.Font.numeric(18))
                        .foregroundStyle(reps >= log.targetReps ? Theme.accentText
                                         : reps == 0 ? Theme.textFaint : Theme.miss)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            reps >= log.targetReps ? Theme.accent.opacity(0.14)
                            : reps == 0 ? Theme.surfaceSunken : Theme.missFill,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
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
}
