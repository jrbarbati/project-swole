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
    @State private var weightAdjustments: [PersistentIdentifier: Double] = [:]

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
            WeekStrip(sessions: finishedSessions)
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

            HStack(spacing: 12) {
                startButton
                swapWorkoutButton
            }
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
                    let unit = settings?.unit ?? .lb
                    let weight = displayWeight(for: exercise, config: config)
                    NextLiftRow(
                        exercise: exercise,
                        config: config,
                        unit: unit,
                        targetWeight: unit.fromLb(weight),
                        delta: unit.fromLb(weight - baselineWeight(for: exercise, config: config)),
                        onDecrement: { adjustWeight(for: exercise, config: config, by: -config.weightIncrement) },
                        onIncrement: { adjustWeight(for: exercise, config: config, by: config.weightIncrement) }
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

    /// Flips which workout comes up next by writing the opposite of it as
    /// `lastCompletedWorkoutType` — WorkoutScheduler derives `next` from that.
    private var swapWorkoutButton: some View {
        Button {
            swapWorkout()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 34, height: 34)
                .overlay(
                    Circle().stroke(Theme.borderStrong, lineWidth: 1)
                )
                .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("swapWorkoutButton")
        .disabled(settings == nil)
    }

    /// Copy under the lift list explaining a hold, e.g. "ROW HELD — 2 MISSES AT 110".
    private var holdNote: String? {
        for entry in nextEntries {
            guard let exercise = entry.exercise, let config = config(for: exercise) else { continue }
            let streak = failStreak(for: exercise)
            guard streak > 0 else { continue }
            let weight = targetWeight(for: exercise, config: config)
            let unit = settings?.unit ?? .lb
            let shortName = exercise.name.split(separator: " ").last.map(String.init) ?? exercise.name
            return "\(shortName) held — \(streak) miss\(streak == 1 ? "" : "es") at \(unit.fromLb(weight).formattedWeight)"
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

    /// The weight to show for this exercise: a pending local adjustment if
    /// the user has tapped −/+, otherwise the calculated plan.
    private func displayWeight(for exercise: Exercise, config: UserExerciseConfig) -> Double {
        weightAdjustments[exercise.persistentModelID] ?? targetWeight(for: exercise, config: config)
    }

    /// What the delta below the weight is measured against: the last
    /// actually-completed weight for this lift, or its starting weight if
    /// it's never been logged.
    private func baselineWeight(for exercise: Exercise, config: UserExerciseConfig) -> Double {
        (try? ProgressionCalculator.lastCompletedWeight(for: exercise, in: modelContext))
            ?? config.startingWeight
    }

    private func adjustWeight(for exercise: Exercise, config: UserExerciseConfig, by delta: Double) {
        let current = displayWeight(for: exercise, config: config)
        weightAdjustments[exercise.persistentModelID] = max(0, current + delta)
    }

    private func failStreak(for exercise: Exercise) -> Int {
        (try? ProgressionCalculator.currentFailStreak(for: exercise, in: modelContext)) ?? 0
    }

    private func startWorkout() {
        do {
            _ = try WorkoutSessionService.startWorkout(in: modelContext, weightOverrides: weightAdjustments)
            weightAdjustments = [:]
        } catch {
            startError = "Couldn't start workout: \(error.localizedDescription)"
        }
    }

    private func swapWorkout() {
        guard let settings else { return }
        settings.lastCompletedWorkoutType = nextWorkoutType
        weightAdjustments = [:]
        try? modelContext.save()
    }
}

// MARK: - Lift row

private struct NextLiftRow: View {
    let exercise: Exercise
    let config: UserExerciseConfig
    let unit: MeasurementUnit
    let targetWeight: Double
    let delta: Double
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    private var plates: PlateMath {
        PlateCalculator.plates(
            for: targetWeight,
            barWeight: PlateCalculator.barWeight(for: unit),
            available: PlateCalculator.plateSet(for: unit)
        )
    }

    /// "+N" ahead of last completed weight, "−N" behind it, "HOLD" if unchanged.
    private var deltaLabel: (text: String, color: Color) {
        if delta == 0 {
            return ("HOLD", Theme.textMuted)
        }
        if delta > 0 {
            return ("+\(delta.formattedWeight)", Theme.accentText)
        }
        return ("−\(abs(delta).formattedWeight)", Theme.warn)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.name)
                    .font(Theme.Font.title(19))
                    .foregroundStyle(Theme.textPrimary)
                MetaLabel(
                    text: "\(config.setCount) × \(config.repsPerSet) · \(plates.shortDescription) \(!plates.perSide.isEmpty ? "per side" : "")",
                    color: Theme.textDim
                )
                .tracking(1.2)
            }
            Spacer()
            HStack(spacing: 10) {
                StepButton(symbol: "−", action: onDecrement)
                    .accessibilityIdentifier("weightDecrement-\(exercise.name)")
                VStack(alignment: .trailing, spacing: 3) {
                    Text(targetWeight.formattedWeight)
                        .font(Theme.Font.numeric(24))
                        .foregroundStyle(Theme.textPrimary)
                    Text(deltaLabel.text)
                        .font(Theme.Font.label())
                        .foregroundStyle(deltaLabel.color)
                }
                StepButton(symbol: "+", action: onIncrement)
                    .accessibilityIdentifier("weightIncrement-\(exercise.name)")
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

// MARK: - Week strip

/// Calendar week, Sunday through Saturday. Filled = a session was finished that day.
/// Today's block always carries a highlighted border; any untrained day with a
/// workout logged before it says REST, whether that day is past or future.
private struct WeekStrip: View {
    let sessions: [WorkoutSession]

    private var days: [(date: Date, trained: Bool, isToday: Bool, isRestDay: Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today)!
        let sessionDates = sessions.map(\.startedAt)
        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: sunday)!
            let trained = sessions.contains { calendar.isDate($0.startedAt, inSameDayAs: day) }
            let isRestDay = RestDayCalculator.isRestDay(day, sessionDates: sessionDates, calendar: calendar)
            return (day, trained, calendar.isDate(day, inSameDayAs: today), isRestDay)
        }
    }

    private var weekdaySymbols: [String] {
        Calendar.current.veryShortWeekdaySymbols
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
                ForEach(Array(days.enumerated()), id: \.1.date) { index, day in
                    VStack(spacing: 4) {
                        Text(weekdaySymbols[index])
                            .font(Theme.Font.label(9))
                            .foregroundStyle(Theme.textDim)
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .fill(day.trained ? Theme.accent.opacity(0.22) : Theme.surfaceSunken)
                            .frame(height: 34)
                            .overlay {
                                if day.isRestDay {
                                    Text("REST")
                                        .font(Theme.Font.label(9))
                                        .tracking(1.0)
                                        .foregroundStyle(Theme.textMuted)
                                }
                            }
                            .overlay {
                                if day.isToday {
                                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                        .strokeBorder(
                                            Theme.borderFocus,
                                            style: day.trained
                                                ? StrokeStyle(lineWidth: 1.5)
                                                : StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                                        )
                                }
                            }
                    }
                }
            }
            HStack {
                MetaLabel(text: "This week", color: Theme.textDim).tracking(1.2)
                Spacer()
                MetaLabel(text: "\(weekStreak) week streak").tracking(1.2)
            }
        }
    }
}
