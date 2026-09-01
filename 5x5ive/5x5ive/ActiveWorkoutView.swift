import SwiftUI
import SwiftData
import SwoleData

struct ActiveWorkoutView: View {
    let session: WorkoutSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var configs: [UserExerciseConfig]
    @Query private var settingsList: [UserSettings]

    @State private var viewModel = ActiveWorkoutViewModel()
    @State private var showFinishConfirmation = false
    @State private var showCancelConfirmation = false
    @State private var showSummary = false
    @State private var detailLog: ExerciseLog?
    @State private var repPickerTarget: PickerTarget?

    private var unit: MeasurementUnit { settingsList.first?.unit ?? .lb }
    private var logs: [ExerciseLog] { session.sortedLogs }
    private var hasUnloggedSets: Bool { logs.contains(where: \.hasUnloggedSets) }

    struct PickerTarget: Identifiable {
        let setLog: SetLog
        let log: ExerciseLog
        var id: PersistentIdentifier { setLog.persistentModelID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let completion = viewModel.completion {
                completionBanner(for: completion)
            }

            if logs.isEmpty {
                emptyState
            } else {
                exerciseList
            }

            RestBar(rest: viewModel.activeRest, onSkip: viewModel.skipRest)
                .padding(.horizontal, Theme.Space.screenTight)

            actionRow
        }
        .background(Theme.canvas)
        .onAppear {
            viewModel.focusFirstIncomplete(in: logs)
            restoreOrClearPersistedRest()
            if let state = currentActivityState() {
                LiveActivityManager.shared.startIfNeeded(workoutTypeRawValue: session.workoutType.rawValue, state: state)
            }
            WorkoutIntentBus.shared.subscribe { action in
                switch action {
                case .skipRest:
                    viewModel.skipRest()
                case .logNextSetAtTarget:
                    // No Log button in the UI yet — nothing to do.
                    break
                }
            }
        }
        .onDisappear { WorkoutIntentBus.shared.unsubscribe() }
        .onChange(of: viewModel.activeRest) { _, newValue in
            syncRestToSession(newValue)
            if let state = currentActivityState() {
                LiveActivityManager.shared.update(state: state)
            }
        }
        .onChange(of: viewModel.completion?.logID) { _, _ in
            // Auto-advance: focus moves as soon as an exercise finishes.
            withAnimation(.snappy) { viewModel.focusFirstIncomplete(in: logs) }
            if let state = currentActivityState() {
                LiveActivityManager.shared.update(state: state)
            }
        }
        .onChange(of: session.loggedSetCount) { _, _ in
            // A set can log (or clear) without starting or ending a rest —
            // e.g. via the rep picker's "Clear set" — which would otherwise
            // leave the widget's tile row stale.
            if let state = currentActivityState() {
                LiveActivityManager.shared.update(state: state)
            }
        }
        .sheet(item: $detailLog) { log in detailSheet(for: log) }
        .sheet(item: $repPickerTarget) { target in repPickerSheet(for: target) }
        .fullScreenCover(isPresented: $showSummary) {
            WorkoutSummaryView(
                session: session,
                onSave: finish,
                onDone: {
                    showSummary = false
                    dismiss()
                },
                onBack: {
                    showSummary = false
                }
            )
        }
        .alert("Cancel this workout?", isPresented: $showCancelConfirmation) {
            Button("Delete Workout", role: .destructive) { cancel() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("This deletes everything logged in this session. This can't be undone.")
        }
        .alert("Some sets aren't logged", isPresented: $showFinishConfirmation) {
            Button("Review & Finish") { showSummary = true }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Any unlogged sets will be recorded as 0 reps. This can't be undone.")
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text("Workout \(session.workoutType.rawValue)")
                    .font(Theme.Font.display(26))
                    .foregroundStyle(Theme.textPrimary)
                ElapsedLabel(since: session.startedAt)
            }
            Spacer()
            Text("\(session.loggedSetCount)/\(session.totalSetCount)")
                .font(Theme.Font.label())
                .tracking(1.4)
                .foregroundStyle(Theme.accentText)
            minimizeButton
        }
        .padding(.top, 10)
        .padding(.horizontal, Theme.Space.screen)
        .padding(.bottom, 18)
    }

    /// Dismisses back to the tab UI without cancelling or finishing the
    /// workout — `RootView`'s active-session query still finds this session,
    /// so it reopens exactly as left when the user taps `ActiveWorkoutBar`.
    private var minimizeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Theme.borderStrong, lineWidth: 1))
                .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("minimizeWorkoutButton")
        .padding(.leading, 10)
    }

    private func completionBanner(for completion: ActiveWorkoutViewModel.Completion) -> some View {
        CompletionBanner(completion: completion) {
            viewModel.undoCompletion(in: logs)
            try? modelContext.save()
        }
        .padding(.horizontal, Theme.Space.screenTight)
        .padding(.bottom, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var emptyState: some View {
        Spacer()
        Text("No exercises in this workout.")
            .font(Theme.Font.body())
            .foregroundStyle(Theme.textMuted)
        Spacer()
    }

    private var exerciseList: some View {
        ScrollView {
            VStack(spacing: Theme.Space.cardGap) {
                ForEach(logs) { log in
                    ExerciseCard(
                        log: log,
                        config: config(for: log),
                        unit: unit,
                        isExpanded: viewModel.expandedLogID == log.persistentModelID,
                        onTapSet: { set in tapSet(set, in: log) },
                        onHoldSet: { set in repPickerTarget = PickerTarget(setLog: set, log: log) },
                        onExpand: { viewModel.expandedLogID = log.persistentModelID },
                        onShowDetail: { detailLog = log }
                    )
                }
            }
            .padding(.horizontal, Theme.Space.screenTight)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                showCancelConfirmation = true
            } label: {
                Text("Cancel")
                    .font(Theme.Font.body(15))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 82, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .stroke(Theme.borderStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                if hasUnloggedSets { showFinishConfirmation = true } else { showSummary = true }
            } label: {
                Text("Finish Workout")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.accentInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Space.screenTight)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: Sheets

    private func detailSheet(for log: ExerciseLog) -> some View {
        NavigationStack {
            ExerciseDetailSheet(log: log, config: config(for: log), unit: unit)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func repPickerSheet(for target: PickerTarget) -> some View {
        RepPickerSheet(
            exerciseName: target.log.exercise?.name ?? "",
            setNumber: target.setLog.setNumber,
            targetReps: target.log.targetReps,
            currentReps: target.setLog.repsCompleted
        ) { reps in
            pickReps(reps, for: target)
        }
        .presentationDetents([.height(300)])
    }

    // MARK: Actions

    private func tapSet(_ set: SetLog, in log: ExerciseLog) {
        guard let config = config(for: log) else { return }
        viewModel.tap(set: set, in: log, isFinalExercise: isFinalExercise(log), config: config)
        try? modelContext.save()
    }

    private func pickReps(_ reps: Int?, for target: PickerTarget) {
        guard let config = config(for: target.log) else { return }
        viewModel.setReps(
            reps,
            for: target.setLog,
            in: target.log,
            isFinalExercise: isFinalExercise(target.log),
            config: config
        )
        try? modelContext.save()
    }

    private func config(for log: ExerciseLog) -> UserExerciseConfig? {
        configs.first { $0.exercise?.persistentModelID == log.exercise?.persistentModelID }
    }

    private func isFinalExercise(_ log: ExerciseLog) -> Bool {
        log.persistentModelID == logs.last?.persistentModelID
    }

    private func finish() -> XPAward? {
        guard let award = try? WorkoutSessionService.finishWorkout(session, in: modelContext) else { return nil }
        #if canImport(HealthKit) && os(iOS)
        let start = session.startedAt
        let end = session.finishedAt ?? .now
        Task { await HealthKitManager.shared.saveWorkout(start: start, end: end) }
        #endif
        LiveActivityManager.shared.end()
        return award
    }

    private func cancel() {
        try? WorkoutSessionService.cancelWorkout(session, in: modelContext)
        LiveActivityManager.shared.end()
        dismiss()
    }

    /// Builds the Live Activity's content state from current view state.
    /// "Current exercise" is whichever log is focused (falls back to the
    /// first log if none is, matching `focusFirstIncomplete`'s own
    /// fallback); "next" is the log immediately after it by `order`.
    private func currentActivityState() -> WorkoutActivityAttributes.ContentState? {
        // `logs` (= `session.sortedLogs`) is already sorted by `order`.
        guard let currentLog = logs.first(where: { $0.persistentModelID == viewModel.expandedLogID }) ?? logs.first else {
            return nil
        }
        let nextLog = logs.first { $0.order > currentLog.order }
        let rest = viewModel.activeRest

        // SetLog relationships come back unordered — sort before mapping, or
        // the widget's tile row reshuffles on every update.
        let orderedSets = currentLog.sortedSets

        // Weight is formatted HERE, in the unit the user has chosen, so the
        // extension never needs UserSettings or the lb/kg conversion.
        let weightLabel = "\(unit.fromLb(currentLog.targetWeight).formattedWeight) \(unit.rawValue)"

        return WorkoutActivityAttributes.ContentState(
            currentExerciseName: currentLog.exercise?.name ?? "",
            completedSets: currentLog.loggedSetCount,
            totalSets: currentLog.sets.count,
            nextExerciseName: nextLog?.exercise?.name,
            restStartDate: rest?.startDate,
            restEndDate: rest?.endDate,
            workoutTypeLabel: session.workoutType.rawValue,
            targetWeightLabel: weightLabel,
            setReps: orderedSets.map(\.repsCompleted),
            targetReps: currentLog.targetReps,
            restDuration: rest.map(\.totalSeconds)
        )
    }

    /// Reconstructs a still-running rest countdown when re-opening a
    /// minimized workout; clears stale rest fields left over from a rest
    /// that finished while the workout was minimized.
    private func restoreOrClearPersistedRest() {
        guard let end = session.restEndDate else { return }
        if end > .now, let start = session.restStartDate, let label = session.restLabel {
            viewModel.restore(startDate: start, endDate: end, label: label)
        } else {
            session.restStartDate = nil
            session.restEndDate = nil
            session.restLabel = nil
            try? modelContext.save()
        }
    }

    /// Mirrors the view model's rest window onto the session so it's
    /// readable from `RootView` (which doesn't own an `ActiveWorkoutViewModel`)
    /// after this view is dismissed.
    private func syncRestToSession(_ rest: ActiveWorkoutViewModel.ActiveRest?) {
        session.restStartDate = rest?.startDate
        session.restEndDate = rest?.endDate
        session.restLabel = rest?.nextUpLabel
        try? modelContext.save()

        if rest != nil {
            // Resolve notification permission now, while the app is
            // foregrounded — a rest just started, so this is the natural
            // moment to ask, and it guarantees permission is already settled
            // by the time the app might background mid-rest.
            Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
        }
    }
}

// MARK: - Elapsed clock

struct ElapsedLabel: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(since))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(Theme.Font.numeric(12))
                .foregroundStyle(Theme.textMuted)
        }
    }
}

// MARK: - Completion banner

struct CompletionBanner: View {
    let completion: ActiveWorkoutViewModel.Completion
    let onUndo: () -> Void

    private var message: String {
        if completion.isFinalExercise {
            return "Workout complete — \(completion.repsSummary)"
        }
        return "\(completion.exerciseName) done — \(completion.repsSummary)"
    }

    var body: some View {
        HStack {
            Text(message)
                .font(Theme.Font.title(15))
                .foregroundStyle(Theme.accentText)
            Spacer()
            Button("UNDO", action: onUndo)
                .font(Theme.Font.label())
                .foregroundStyle(Theme.accentText)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Theme.Space.cardPadding)
        .background(Theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .stroke(Theme.accent.opacity(0.32), lineWidth: 1)
        )
    }
}

// MARK: - sheet(item:) shim

extension View {
    func sheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )) {
            if let value = item.wrappedValue { content(value) }
        }
    }
}
