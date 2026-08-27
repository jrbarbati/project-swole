import Foundation
import SwiftData
import Observation

@Observable
public final class ActiveWorkoutViewModel: @unchecked Sendable {
    public struct ActiveRest: Equatable {
        public let outcome: RestOutcome
        public let endDate: Date
    }

    public struct TransitionPrompt: Equatable {
        public let exerciseName: String
        public let isFinalExercise: Bool
    }

    public private(set) var activeRest: ActiveRest?
    public private(set) var transitionPrompt: TransitionPrompt?

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
