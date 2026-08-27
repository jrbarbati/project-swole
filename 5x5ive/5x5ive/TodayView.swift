import SwiftUI
import SwiftData
import SwoleData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [UserSettings]
    @Query(sort: \WorkoutTemplateExercise.order) private var templateEntries: [WorkoutTemplateExercise]
    @Query private var configs: [UserExerciseConfig]
    @Query(filter: #Predicate<WorkoutSession> { $0.finishedAt != nil },
           sort: \WorkoutSession.startedAt, order: .reverse)
    private var finishedSessions: [WorkoutSession]

    @State private var startError: String?

    private var settings: UserSettings? { settingsList.first }

    private var nextWorkoutType: WorkoutType {
        guard let settings else { return .a }
        return WorkoutScheduler.nextWorkoutType(after: settings)
    }

    private var nextEntries: [WorkoutTemplateExercise] {
        templateEntries.filter { $0.workoutType == nextWorkoutType }
    }

    private var totalSets: Int {
        nextEntries.reduce(0) { total, entry in
            total + (config(for: entry.exercise)?.setCount ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StreakStrip(sessions: finishedSessions)
                .padding(.top, 22)
                .padding(.horizontal, Theme.Space.screen)

            liftList
                .padding(.top, 26)
                .padding(.horizontal, Theme.Space.screen)

            Spacer(minLength: 0)

            if let startError {
                Text(startError)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.miss)
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.bottom, 10)
            }

            startButton
                .padding(.horizontal, Theme.Space.screen)
                .padding(.bottom, 12)
        }
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var liftList: some View {
        VStack(spacing: Theme.Space.cardGap) {
            ForEach(nextEntries) { entry in
                if let exercise = entry.exercise, let config = config(for: exercise) {
                    NextLiftRow(
                        exercise: exercise,
                        config: config,
                        unit: settings?.unit ?? .lb,
                        targetWeight: targetWeight(for: exercise, config: config),
                        failStreak: failStreak(for: exercise)
                    )
                }
            }
            if let holdNote {
                MetaLabel(text: holdNote, color: Theme.textFaint)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var startButton: some View {
        Button {
            startWorkout()
        } label: {
            Text("Start Workout \(nextWorkoutType.rawValue)")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.accentInk)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(settings == nil)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetaLabel(text: Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Workout \(nextWorkoutType.rawValue)")
                    .font(Theme.Font.display(40))
                    .foregroundStyle(Theme.textPrimary)
                MetaLabel(text: "\(nextEntries.count) lifts · \(totalSets) sets", color: Theme.textDim)
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, Theme.Space.screen)
    }

    /// Copy under the lift list explaining a hold, e.g. "ROW HELD — 2 MISSES AT 110".
    private var holdNote: String? {
        for entry in nextEntries {
            guard let exercise = entry.exercise, let config = config(for: exercise) else { continue }
            let streak = failStreak(for: exercise)
            guard streak > 0 else { continue }
            let weight = targetWeight(for: exercise, config: config)
            let shortName = exercise.name.split(separator: " ").last.map(String.init) ?? exercise.name
            return "\(shortName) held — \(streak) miss\(streak == 1 ? "" : "es") at \(weight.formatted())"
        }
        return nil
    }

    private func config(for exercise: Exercise?) -> UserExerciseConfig? {
        guard let exercise else { return nil }
        return configs.first { $0.exercise?.persistentModelID == exercise.persistentModelID }
    }

    private func targetWeight(for exercise: Exercise, config: UserExerciseConfig) -> Double {
        (try? ProgressionCalculator.nextTargetWeight(for: exercise, config: config, in: modelContext))
            ?? config.startingWeight
    }

    private func failStreak(for exercise: Exercise) -> Int {
        (try? ProgressionCalculator.currentFailStreak(for: exercise, in: modelContext)) ?? 0
    }

    private func startWorkout() {
        do {
            _ = try WorkoutSessionService.startWorkout(in: modelContext)
        } catch {
            startError = "Couldn't start workout: \(error.localizedDescription)"
        }
    }
}

// MARK: - Lift row

private struct NextLiftRow: View {
    let exercise: Exercise
    let config: UserExerciseConfig
    let unit: MeasurementUnit
    let targetWeight: Double
    let failStreak: Int

    private var plates: PlateMath {
        PlateCalculator.plates(
            for: targetWeight,
            barWeight: PlateCalculator.barWeight(for: unit),
            available: PlateCalculator.plateSet(for: unit)
        )
    }

    /// "+5" when progressing, "HOLD" when repeating the weight, "DELOAD" on a drop.
    private var deltaLabel: (text: String, color: Color) {
        if failStreak >= config.deloadThreshold { return ("DELOAD", Theme.warn) }
        if failStreak > 0 { return ("HOLD", Theme.textMuted) }
        return ("+\(config.weightIncrement.formatted())", Theme.accentText)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.name)
                    .font(Theme.Font.title(19))
                    .foregroundStyle(Theme.textPrimary)
                MetaLabel(
                    text: "\(config.setCount) × \(config.repsPerSet) · \(plates.shortDescription) per side",
                    color: Theme.textDim
                )
                .tracking(1.2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(targetWeight.formatted(.number.precision(.fractionLength(0...1))))
                    .font(Theme.Font.numeric(24))
                    .foregroundStyle(Theme.textPrimary)
                Text(deltaLabel.text)
                    .font(Theme.Font.label())
                    .foregroundStyle(deltaLabel.color)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Streak strip

/// Seven blocks, one per day. Filled = a session was finished that day.
/// The trailing dashed block is today when nothing is logged yet.
private struct StreakStrip: View {
    let sessions: [WorkoutSession]

    private var days: [(date: Date, trained: Bool, isToday: Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let trained = sessions.contains { calendar.isDate($0.startedAt, inSameDayAs: day) }
            return (day, trained, offset == 0)
        }
    }

    private var weekStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var cursor = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        while sessions.contains(where: { calendar.isDate($0.startedAt, equalTo: cursor, toGranularity: .weekOfYear) }) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                ForEach(days, id: \.date) { day in
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(day.trained ? Theme.accent.opacity(0.22) : Theme.surfaceSunken)
                        .frame(height: 34)
                        .overlay {
                            if day.isToday && !day.trained {
                                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                    .strokeBorder(Theme.borderFocus, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            }
                        }
                }
            }
            HStack {
                MetaLabel(text: "Last 7 days", color: Theme.textDim).tracking(1.2)
                Spacer()
                MetaLabel(text: "\(weekStreak) week streak").tracking(1.2)
            }
        }
    }
}
