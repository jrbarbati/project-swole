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
    @State private var sheetLog: ExerciseLog?
    @State private var picker: PickerTarget?

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
                CompletionBanner(completion: completion) {
                    viewModel.undoCompletion(in: logs)
                    try? modelContext.save()
                }
                .padding(.horizontal, Theme.Space.screenTight)
                .padding(.bottom, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if logs.isEmpty {
                Spacer()
                Text("No exercises in this workout.")
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: Theme.Space.cardGap) {
                        ForEach(logs) { log in
                            ExerciseCard(
                                log: log,
                                config: config(for: log),
                                unit: unit,
                                isExpanded: viewModel.expandedLogID == log.persistentModelID,
                                onTapSet: { set in tap(set, in: log) },
                                onHoldSet: { set in picker = PickerTarget(setLog: set, log: log) },
                                onExpand: { viewModel.expandedLogID = log.persistentModelID },
                                onShowDetail: { sheetLog = log }
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Space.screenTight)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
            }

            RestBar(rest: viewModel.activeRest, onSkip: viewModel.skipRest)
                .padding(.horizontal, Theme.Space.screenTight)

            actionRow
        }
        .background(Theme.canvas)
        .onAppear { viewModel.focusFirstIncomplete(in: logs) }
        .onChange(of: viewModel.completion?.logID) { _, _ in
            // Auto-advance: focus moves as soon as an exercise finishes.
            withAnimation(.snappy) { viewModel.focusFirstIncomplete(in: logs) }
        }
        .sheet(item: $sheetLog) { log in
            NavigationStack {
                ExerciseDetailSheet(log: log, config: config(for: log), unit: unit)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .sheet(item: $picker) { target in
            RepPickerSheet(
                exerciseName: target.log.exercise?.name ?? "",
                setNumber: target.setLog.setNumber,
                targetReps: target.log.targetReps,
                current: target.setLog.repsCompleted
            ) { reps in
                guard let config = config(for: target.log) else { return }
                viewModel.setReps(
                    reps,
                    for: target.setLog,
                    in: target.log,
                    isFinalExercise: isFinal(target.log),
                    config: config
                )
                try? modelContext.save()
            }
            .presentationDetents([.height(300)])
        }
        .fullScreenCover(isPresented: $showSummary) {
            WorkoutSummaryView(session: session) {
                finish()
            } onBack: {
                showSummary = false
            }
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
        }
        .padding(.top, 10)
        .padding(.horizontal, Theme.Space.screen)
        .padding(.bottom, 18)
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

    // MARK: Actions

    private func tap(_ set: SetLog, in log: ExerciseLog) {
        guard let config = config(for: log) else { return }
        viewModel.tap(set: set, in: log, isFinalExercise: isFinal(log), config: config)
        try? modelContext.save()
    }

    private func config(for log: ExerciseLog) -> UserExerciseConfig? {
        configs.first { $0.exercise?.persistentModelID == log.exercise?.persistentModelID }
    }

    private func isFinal(_ log: ExerciseLog) -> Bool {
        log.persistentModelID == logs.last?.persistentModelID
    }

    private func finish() {
        try? WorkoutSessionService.finishWorkout(session, in: modelContext)
        dismiss()
    }

    private func cancel() {
        try? WorkoutSessionService.cancelWorkout(session, in: modelContext)
        dismiss()
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

// MARK: - Completion banner (replaces TransitionPromptView)

struct CompletionBanner: View {
    let completion: ActiveWorkoutViewModel.Completion
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text(completion.isFinalExercise
                 ? "Workout complete — \(completion.repsSummary)"
                 : "\(completion.exerciseName) done — \(completion.repsSummary)")
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
