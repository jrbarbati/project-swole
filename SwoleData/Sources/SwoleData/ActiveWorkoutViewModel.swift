import Foundation
import SwiftData
import Observation

@Observable
@MainActor
public final class ActiveWorkoutViewModel {

    public struct ActiveRest: Equatable {
        public let outcome: RestOutcome
        public let startDate: Date
        public let endDate: Date
        public let nextUpLabel: String

        public init(outcome: RestOutcome, startDate: Date, endDate: Date, nextUpLabel: String) {
            self.outcome = outcome
            self.startDate = startDate
            self.endDate = endDate
            self.nextUpLabel = nextUpLabel
        }

        public var totalSeconds: TimeInterval { endDate.timeIntervalSince(startDate) }

        public func remaining(at date: Date) -> Int {
            max(0, Int(endDate.timeIntervalSince(date).rounded(.up)))
        }

        /// 0…1 elapsed.
        public func progress(at date: Date) -> Double {
            guard totalSeconds > 0 else { return 1 }
            return min(1, max(0, date.timeIntervalSince(startDate) / totalSeconds))
        }
    }

    public struct Completion: Equatable {
        public let logID: PersistentIdentifier
        public let exerciseName: String
        public let repsSummary: String
        public let isFinalExercise: Bool

        public init(logID: PersistentIdentifier, exerciseName: String, repsSummary: String, isFinalExercise: Bool) {
            self.logID = logID
            self.exerciseName = exerciseName
            self.repsSummary = repsSummary
            self.isFinalExercise = isFinalExercise
        }
    }

    public private(set) var activeRest: ActiveRest?
    public private(set) var completion: Completion?
    public var expandedLogID: PersistentIdentifier?

    private(set) var settleFireCount = 0

    private let settleDelay: Duration
    private var pendingSettleTasks: [PersistentIdentifier: Task<Void, Never>] = [:]
    private var completionDismissTask: Task<Void, Never>?

    public init(settleDelay: Duration = .milliseconds(1500)) {
        self.settleDelay = settleDelay
    }

    // MARK: - Logging

    /// Tap cycles nil → target → target-1 … → 0 → nil.
    public func tap(set: SetLog, in log: ExerciseLog, isFinalExercise: Bool, config: UserExerciseConfig) {
        set.repsCompleted = RepCycle.next(current: set.repsCompleted, target: log.targetReps)
        scheduleSettle(for: set, in: log, isFinalExercise: isFinalExercise, config: config)
    }

    /// `nil` clears the set.
    public func setReps(_ reps: Int?, for set: SetLog, in log: ExerciseLog, isFinalExercise: Bool, config: UserExerciseConfig) {
        set.repsCompleted = reps
        scheduleSettle(for: set, in: log, isFinalExercise: isFinalExercise, config: config)
    }

    public func skipRest() {
        activeRest = nil
    }

    public func dismissCompletion() {
        completionDismissTask?.cancel()
        completion = nil
    }

    /// Clears the last logged set of the completed exercise and refocuses it.
    public func undoCompletion(in logs: [ExerciseLog]) {
        guard let completion,
              let log = logs.first(where: { $0.persistentModelID == completion.logID }) else { return }

        if let lastSet = log.sortedSets.last {
            lastSet.repsCompleted = nil
        }
        activeRest = nil
        expandedLogID = completion.logID
        dismissCompletion()
    }

    // MARK: - Auto-advance

    public func focusFirstIncomplete(in logs: [ExerciseLog]) {
        let sortedLogs = logs.sorted { $0.order < $1.order }
        expandedLogID = (sortedLogs.first { $0.hasUnloggedSets } ?? sortedLogs.last)?.persistentModelID
    }

    // MARK: - Private

    private func scheduleSettle(for set: SetLog, in log: ExerciseLog, isFinalExercise: Bool, config: UserExerciseConfig) {
        let setID = set.persistentModelID
        pendingSettleTasks[setID]?.cancel()

        let settledReps = set.repsCompleted
        let targetReps = log.targetReps
        let exerciseName = log.exercise?.name ?? ""
        let logID = log.persistentModelID
        let restOnSuccess = config.restSecondsOnSuccess
        let restOnFail = config.restSecondsOnFail
        let delay = settleDelay

        // Snapshot what the exercise looks like once this value settles.
        let sortedSets = log.sortedSets
        let exerciseIsComplete = sortedSets.allSatisfy { $0.repsCompleted != nil }
        let repsSummary = log.repsSummary
        let nextSetNumber = sortedSets.first { $0.repsCompleted == nil }?.setNumber

        pendingSettleTasks[setID] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }

            pendingSettleTasks[setID] = nil
            guard let settledReps else { return }

            settleFireCount += 1
            let outcome: RestOutcome = settledReps >= targetReps ? .success : .fail

            if exerciseIsComplete {
                publishCompletion(
                    Completion(
                        logID: logID,
                        exerciseName: exerciseName,
                        repsSummary: repsSummary,
                        isFinalExercise: isFinalExercise
                    )
                )
            }

            // Rest still runs between exercises — only the final set of the
            // final exercise ends without one.
            let endsWorkout = exerciseIsComplete && isFinalExercise
            guard !endsWorkout else {
                activeRest = nil
                return
            }

            startRest(
                outcome: outcome,
                seconds: outcome == .success ? restOnSuccess : restOnFail,
                label: Self.restLabel(exerciseIsComplete: exerciseIsComplete, nextSetNumber: nextSetNumber)
            )
        }
    }

    private static func restLabel(exerciseIsComplete: Bool, nextSetNumber: Int?) -> String {
        if exerciseIsComplete {
            return "Rest · next exercise"
        }
        if let nextSetNumber {
            return "Rest · set \(nextSetNumber) next"
        }
        return "Rest"
    }

    private func startRest(outcome: RestOutcome, seconds: Int, label: String) {
        let now = Date()
        activeRest = ActiveRest(
            outcome: outcome,
            startDate: now,
            endDate: now.addingTimeInterval(TimeInterval(seconds)),
            nextUpLabel: label
        )
    }

    private func publishCompletion(_ value: Completion) {
        completion = value
        completionDismissTask?.cancel()
        completionDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.completion = nil
        }
    }
}

// MARK: - Convenience

public extension ExerciseLog {
    var hasUnloggedSets: Bool { sets.contains { $0.repsCompleted == nil } }

    var sortedSets: [SetLog] { sets.sorted { $0.setNumber < $1.setNumber } }

    /// "5 5 5 3 –"
    var repsSummary: String {
        sortedSets.map { $0.repsCompleted.map(String.init) ?? "–" }.joined(separator: " ")
    }

    var loggedSetCount: Int { sets.filter { $0.repsCompleted != nil }.count }

    var volume: Double {
        sortedSets.reduce(0) { $0 + Double($1.repsCompleted ?? 0) * targetWeight }
    }
}

public extension WorkoutSession {
    var sortedLogs: [ExerciseLog] { exerciseLogs.sorted { $0.order < $1.order } }
    var totalSetCount: Int { exerciseLogs.reduce(0) { $0 + $1.sets.count } }
    var loggedSetCount: Int { exerciseLogs.reduce(0) { $0 + $1.loggedSetCount } }
    var volume: Double { exerciseLogs.reduce(0) { $0 + $1.volume } }
}
