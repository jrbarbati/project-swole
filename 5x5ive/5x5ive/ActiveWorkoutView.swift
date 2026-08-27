import SwiftUI
import SwiftData
import SwoleData

struct ActiveWorkoutView: View {
    let session: WorkoutSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var configs: [UserExerciseConfig]
    @State private var viewModel = ActiveWorkoutViewModel()
    @State private var currentIndex: Int
    @State private var showFinishConfirmation = false
    @State private var showCancelConfirmation = false

    init(session: WorkoutSession) {
        self.session = session
        let logs = session.exerciseLogs.sorted { $0.order < $1.order }
        let firstIncomplete = logs.firstIndex { log in log.sets.contains { $0.repsCompleted == nil } }
        _currentIndex = State(initialValue: firstIncomplete ?? max(0, logs.count - 1))
    }

    private var sortedLogs: [ExerciseLog] {
        session.exerciseLogs.sorted { $0.order < $1.order }
    }

    private var hasUnloggedSets: Bool {
        sortedLogs.contains { log in log.sets.contains { $0.repsCompleted == nil } }
    }

    var body: some View {
        VStack {
            if sortedLogs.isEmpty {
                Text("No exercises in this workout.")
            } else {
                let log = sortedLogs[currentIndex]
                let config = configs.first { $0.exercise?.persistentModelID == log.exercise?.persistentModelID }

                HStack {
                    Button("←") { currentIndex -= 1 }
                        .disabled(currentIndex == 0)
                    Spacer()
                    Text("\(log.exercise?.name ?? "") \(currentIndex + 1)/\(sortedLogs.count)")
                        .font(.headline)
                    Spacer()
                    Button("→") { currentIndex += 1 }
                        .disabled(currentIndex == sortedLogs.count - 1)
                }
                .padding(.horizontal)

                if let config {
                    ExerciseSetsView(log: log, isEditable: true) { set in
                        let sortedSets = log.sets.sorted { $0.setNumber < $1.setNumber }
                        let isLastSet = set.setNumber == sortedSets.last?.setNumber
                        viewModel.tap(
                            set: set,
                            in: log,
                            isLastSet: isLastSet,
                            isFinalExercise: currentIndex == sortedLogs.count - 1,
                            config: config
                        )
                        try? modelContext.save()
                    }
                } else {
                    Text("Missing configuration for \(log.exercise?.name ?? "this exercise").")
                }

                Spacer()

                if let activeRest = viewModel.activeRest {
                    RestTimerBanner(rest: activeRest)
                }
            }
        }
        .padding(.top)
        .overlay {
            if let prompt = viewModel.transitionPrompt {
                TransitionPromptView(prompt: prompt) {
                    viewModel.dismissTransitionPrompt()
                    if !prompt.isFinalExercise, currentIndex < sortedLogs.count - 1 {
                        currentIndex += 1
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel Workout", role: .destructive) {
                    showCancelConfirmation = true
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Finish Workout") {
                    if hasUnloggedSets {
                        showFinishConfirmation = true
                    } else {
                        finish()
                    }
                }
            }
        }
        .alert("Some sets aren't logged", isPresented: $showFinishConfirmation) {
            Button("Finish Anyway", role: .destructive) { finish() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Any unlogged sets will be recorded as 0 reps. This can't be undone.")
        }
        .alert("Cancel this workout?", isPresented: $showCancelConfirmation) {
            Button("Delete Workout", role: .destructive) { cancel() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("This deletes everything logged in this session. This can't be undone.")
        }
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
