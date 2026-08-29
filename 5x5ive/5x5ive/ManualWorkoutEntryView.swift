import SwiftUI
import SwiftData
import SwoleData

/// Backfills or edits a workout for a day the user didn't log live. Reuses
/// the tap-to-cycle/long-press rep tiles from the active-workout flow but
/// writes are immediate — no rest bar, no settle delay, since there's
/// nothing to rest between when the sets already happened.
struct ManualWorkoutEntryView: View {
    /// `nil` starts the add flow (date + type picker first); otherwise this
    /// existing session's logs are edited in place.
    let existingSession: WorkoutSession?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query private var allTemplateEntries: [WorkoutTemplateExercise]
    @Query private var allConfigs: [UserExerciseConfig]
    @Query private var settingsList: [UserSettings]

    @State private var date: Date = .now
    @State private var workoutType: WorkoutType = .a
    @State private var entries: [ManualEntry] = []
    @State private var didPickDetails = false
    @State private var repPickerTarget: RepPickerTarget?

    private var unit: MeasurementUnit { settingsList.first?.unit ?? .lb }
    private var isAddMode: Bool { existingSession == nil }
    private var showsEditor: Bool { !isAddMode || didPickDetails }

    struct RepPickerTarget: Identifiable {
        let entryID: PersistentIdentifier
        let setIndex: Int
        var id: String { "\(entryID)-\(setIndex)" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if showsEditor {
                    editorList
                        .padding(.top, 22)
                } else {
                    detailsPicker
                        .padding(.top, 22)
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $repPickerTarget) { target in repPickerSheet(for: target) }
        .task { loadExistingSession() }
    }

    // MARK: Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(isAddMode ? "Log Past Workout" : "Edit Workout")
                    .font(Theme.Font.display(30))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                cancelButton
            }
            MetaLabel(text: date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
        }
        .padding(.top, 14)
    }

    private var cancelButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Cancel")
                .font(Theme.Font.body(14))
                .foregroundStyle(Theme.textMuted)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .stroke(Theme.borderStrong, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 1 — date + type (add mode only)

    private var detailsPicker: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                MetaLabel(text: "Date").tracking(1.6)
                DatePicker("", selection: $date, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.accent)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 10) {
                MetaLabel(text: "Workout Type").tracking(1.6)
                HStack(spacing: 10) {
                    ForEach(WorkoutType.allCases, id: \.self) { type in
                        typeButton(type)
                    }
                }
            }

            Button {
                loadTemplate(for: workoutType)
                didPickDetails = true
            } label: {
                Text("Continue")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.accentInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(templateEntries(for: workoutType).isEmpty)
        }
    }

    private func typeButton(_ type: WorkoutType) -> some View {
        let isSelected = type == workoutType
        return Button {
            workoutType = type
        } label: {
            Text("Workout \(type.rawValue)")
                .font(Theme.Font.title(15))
                .foregroundStyle(isSelected ? Theme.accentText : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    isSelected ? Theme.accent.opacity(0.14) : Theme.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .stroke(isSelected ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 2 — editor

    private var editorList: some View {
        VStack(spacing: Theme.Space.cardGap) {
            ForEach($entries) { $entry in
                ManualExerciseCard(
                    entry: $entry,
                    unit: unit,
                    onTapSet: { index in cycleReps(for: entry.id, setIndex: index) },
                    onHoldSet: { index in repPickerTarget = RepPickerTarget(entryID: entry.id, setIndex: index) }
                )
            }

            saveButton
                .padding(.top, 8)
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Save Workout")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.accentInk)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func repPickerSheet(for target: RepPickerTarget) -> some View {
        let entryIndex = entries.firstIndex { $0.id == target.entryID }
        let entry = entryIndex.map { entries[$0] }
        return RepPickerSheet(
            exerciseName: entry?.exerciseName ?? "",
            setNumber: target.setIndex + 1,
            targetReps: entry?.targetReps ?? 0,
            currentReps: entry?.reps[target.setIndex] ?? nil
        ) { reps in
            setReps(reps, for: target.entryID, setIndex: target.setIndex)
        }
        .presentationDetents([.height(300)])
    }

    // MARK: Data loading

    private func templateEntries(for type: WorkoutType) -> [WorkoutTemplateExercise] {
        allTemplateEntries.filter { $0.workoutType == type }.sorted { $0.order < $1.order }
    }

    private func config(for exercise: Exercise) -> UserExerciseConfig? {
        allConfigs.first { $0.exercise?.persistentModelID == exercise.persistentModelID }
    }

    private func loadTemplate(for type: WorkoutType) {
        entries = templateEntries(for: type).compactMap { templateEntry in
            guard let exercise = templateEntry.exercise, let config = config(for: exercise) else { return nil }
            let targetWeight = (try? ProgressionCalculator.nextTargetWeight(for: exercise, config: config, in: modelContext))
                ?? config.startingWeight
            return ManualEntry(
                exerciseID: exercise.persistentModelID,
                exerciseName: exercise.name,
                targetWeight: targetWeight,
                weightIncrement: config.weightIncrement,
                targetReps: config.repsPerSet,
                reps: Array(repeating: nil, count: config.setCount)
            )
        }
    }

    private func loadExistingSession() {
        guard let session = existingSession else { return }
        date = session.startedAt
        workoutType = session.workoutType
        entries = session.sortedLogs.compactMap { log in
            guard let exercise = log.exercise else { return nil }
            return ManualEntry(
                exerciseID: exercise.persistentModelID,
                exerciseName: exercise.name,
                targetWeight: log.targetWeight,
                weightIncrement: config(for: exercise)?.weightIncrement ?? 5,
                targetReps: log.targetReps,
                reps: log.sortedSets.map(\.repsCompleted)
            )
        }
    }

    // MARK: Editing

    private func cycleReps(for entryID: PersistentIdentifier, setIndex: Int) {
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let current = entries[entryIndex].reps[setIndex]
        entries[entryIndex].reps[setIndex] = RepCycle.next(current: current, target: entries[entryIndex].targetReps)
    }

    private func setReps(_ reps: Int?, for entryID: PersistentIdentifier, setIndex: Int) {
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[entryIndex].reps[setIndex] = reps
    }

    // MARK: Save

    private func save() {
        if let session = existingSession {
            saveEdits(to: session)
        } else {
            saveNewSession()
        }
        try? modelContext.save()
        dismiss()
    }

    private func saveEdits(to session: WorkoutSession) {
        for entry in entries {
            guard let log = session.exerciseLogs.first(where: { $0.exercise?.persistentModelID == entry.exerciseID }) else { continue }
            log.targetWeight = entry.targetWeight
            for (setLog, reps) in zip(log.sortedSets, entry.reps) {
                setLog.repsCompleted = reps
            }
            // A corrected log supersedes any pending manual nudge for this
            // exercise — otherwise the override would keep shadowing this
            // edit forever, the same way WorkoutSessionService clears it
            // when a live workout starts.
            if let exercise = log.exercise {
                config(for: exercise)?.weightOverride = nil
            }
        }
    }

    private func saveNewSession() {
        let session = WorkoutSession(startedAt: date, workoutType: workoutType, finishedAt: date)
        modelContext.insert(session)

        for (order, entry) in entries.enumerated() {
            guard let exercise = allExercises.first(where: { $0.persistentModelID == entry.exerciseID }) else { continue }
            let log = ExerciseLog(
                session: session,
                exercise: exercise,
                targetWeight: entry.targetWeight,
                targetReps: entry.targetReps,
                order: order
            )
            modelContext.insert(log)
            for (index, reps) in entry.reps.enumerated() {
                modelContext.insert(SetLog(exerciseLog: log, setNumber: index + 1, repsCompleted: reps))
            }
            // Backfilling real history for this exercise supersedes any
            // pending manual nudge, the same way starting a live workout
            // consumes it — otherwise it would keep shadowing this log.
            config(for: exercise)?.weightOverride = nil
        }
    }
}

// MARK: - Entry model

private struct ManualEntry: Identifiable {
    let exerciseID: PersistentIdentifier
    let exerciseName: String
    var targetWeight: Double
    let weightIncrement: Double
    let targetReps: Int
    var reps: [Int?]

    var id: PersistentIdentifier { exerciseID }
}

// MARK: - Exercise card

private struct ManualExerciseCard: View {
    @Binding var entry: ManualEntry
    let unit: MeasurementUnit
    let onTapSet: (Int) -> Void
    let onHoldSet: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.exerciseName)
                    .font(Theme.Font.title(18))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                weightStepper
            }

            HStack(spacing: Theme.Space.tileGap) {
                ForEach(Array(entry.reps.enumerated()), id: \.offset) { index, reps in
                    SetTile(reps: reps, targetReps: entry.targetReps, isNext: false)
                        .onTapGesture { onTapSet(index) }
                        .onLongPressGesture(minimumDuration: 0.35) { onHoldSet(index) }
                        .accessibilityLabel("Set \(index + 1)")
                        .accessibilityValue(reps.map { "\($0) reps" } ?? "not logged")
                        .accessibilityHint("Tap to cycle reps down. Touch and hold to pick a number.")
                        .accessibilityIdentifier("manualSet\(index + 1)-\(entry.exerciseName)")
                }
            }
        }
        .padding(Theme.Space.cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var weightStepper: some View {
        HStack(spacing: 10) {
            StepButton(symbol: "−") {
                entry.targetWeight = max(0, entry.targetWeight - entry.weightIncrement)
            }
            .accessibilityIdentifier("manualWeightDecrement-\(entry.exerciseName)")
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(unit.fromLb(entry.targetWeight).formattedWeight)
                    .font(Theme.Font.numeric(15))
                    .foregroundStyle(Theme.textMuted)
                Text(unit.rawValue.uppercased())
                    .font(Theme.Font.numeric(15))
                    .foregroundStyle(Theme.textMuted)
            }
            .accessibilityIdentifier("manualWeight-\(entry.exerciseName)")
            StepButton(symbol: "+") {
                entry.targetWeight += entry.weightIncrement
            }
            .accessibilityIdentifier("manualWeightIncrement-\(entry.exerciseName)")
        }
    }
}
