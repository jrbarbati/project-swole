import Foundation
import SwiftData
import Observation

@Observable
@MainActor
public final class ActiveWorkoutViewModel {
    public struct ActiveRest: Equatable {
        public let outcome: RestOutcome
        public let endDate: Date

        public init(outcome: RestOutcome, endDate: Date) {
            self.outcome = outcome
            self.endDate = endDate
        }
    }

    public struct TransitionPrompt: Equatable {
        public let exerciseName: String
        public let isFinalExercise: Bool

        public init(exerciseName: String, isFinalExercise: Bool) {
            self.exerciseName = exerciseName
            self.isFinalExercise = isFinalExercise
        }
    }

    public private(set) var activeRest: ActiveRest?
    public private(set) var transitionPrompt: TransitionPrompt?

    /// Number of settle tasks that have actually run to completion (past cancellation and
    /// nil-value guards) and mutated `activeRest`/`transitionPrompt`. Exposed for testing the
    /// debounce/cancellation guarantee — production code should not rely on this.
    private(set) var settleFireCount = 0

    private let settleDelay: Duration
    private var pendingSettleTasks: [PersistentIdentifier: Task<Void, Never>] = [:]

    public init(settleDelay: Duration = .milliseconds(1500)) {
        self.settleDelay = settleDelay
    }

    public func dismissTransitionPrompt() {
        transitionPrompt = nil
    }

    public func tap(set: SetLog, in log: ExerciseLog, isLastSet: Bool, isFinalExercise: Bool, config: UserExerciseConfig) {
        set.repsCompleted = RepCycle.next(current: set.repsCompleted, target: log.targetReps)

        let setID = set.persistentModelID
        pendingSettleTasks[setID]?.cancel()

        let capturedValue = set.repsCompleted
        let targetReps = log.targetReps
        let exerciseName = log.exercise?.name ?? ""
        let restSecondsOnSuccess = config.restSecondsOnSuccess
        let restSecondsOnFail = config.restSecondsOnFail
        let delay = settleDelay

        pendingSettleTasks[setID] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pendingSettleTasks[setID] = nil
            guard let value = capturedValue else { return }

            self?.settleFireCount += 1

            let outcome: RestOutcome = value >= targetReps ? .success : .fail
            if isLastSet {
                self?.transitionPrompt = TransitionPrompt(exerciseName: exerciseName, isFinalExercise: isFinalExercise)
            } else {
                let seconds = outcome == .success ? restSecondsOnSuccess : restSecondsOnFail
                self?.activeRest = ActiveRest(outcome: outcome, endDate: Date().addingTimeInterval(TimeInterval(seconds)))
            }
        }
    }
}
