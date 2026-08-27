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
        /// Copy for the docked bar, e.g. "REST · SET 5 NEXT".
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

        /// 0…1 elapsed, for the bar's progress track.
        public func progress(at date: Date) -> Double {
            guard totalSeconds > 0 else { return 1 }
            return min(1, max(0, date.timeIntervalSince(startDate) / totalSeconds))
        }
    }

    /// Non-blocking "Squat done — 5 5 5 3 5 · UNDO" banner.
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
    /// Which exercise card is expanded. Set on appear, then moved by auto-advance.
    public var expandedLogID: PersistentIdentifier?

    private(set) var settleFireCount = 0

    private let settleDelay: Duration
    private var pendingSettleTasks: [PersistentIdentifier: Task<Void, Never>] = [:]
    private var completionDismissTask: Task<Void, Never>?

    public init(settleDelay: Duration = .milliseconds(1500)) {
        self.settleDelay = settleDelay
    }

    // MARK: - Logging

    /// Primary interaction: tap cycles nil → target → target-1 … → 0 → nil.
    public func tap(set: SetLog, in log: ExerciseLog, isFinalExercise: Bool, config: UserExerciseConfig) {
        set.repsCompleted = RepCycle.next(current: set.repsCompleted, target: log.targetReps)
        scheduleSettle(for: set, in: log, isFinalExercise: isFinalExercise, config: config)
    }

    /// Secondary interaction: long-press opens the rep picker, which sets a value directly.
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

    /// Undo in the completion banner: clears the last logged set of that exercise
    /// and pulls focus back to it.
    public func undoCompletion(in logs: [ExerciseLog]) {
        guard let completion,
              let log = logs.first(where: { $0.persistentModelID == completion.logID }) else { return }

        if let last = log.sets.sorted(by: { $0.setNumber < $1.setNumber }).last {
            last.repsCompleted = nil
        }
        activeRest = nil
        expandedLogID = completion.logID
        dismissCompletion()
    }

    // MARK: - Auto-advance

    /// Called on appear and after each exercise finishes.
    public func focusFirstIncomplete(in logs: [ExerciseLog]) {
        let sorted = logs.sorted { $0.order < $1.order }
        expandedLogID = (sorted.first { $0.hasUnloggedSets } ?? sorted.last)?.persistentModelID
    }

    // MARK: - Private

    private func scheduleSettle(for set: SetLog, in log: ExerciseLog, isFinalExercise: Bool, config: UserExerciseConfig) {
        let setID = set.persistentModelID
        pendingSettleTasks[setID]?.cancel()

        let capturedValue = set.repsCompleted
        let targetReps = log.targetReps
        let exerciseName = log.exercise?.name ?? ""
        let logID = log.persistentModelID
        let restOnSuccess = config.restSecondsOnSuccess
        let restOnFail = config.restSecondsOnFail
        let delay = settleDelay

        // Snapshot what the exercise looks like once this value settles.
        let sortedSets = log.sets.sorted { $0.setNumber < $1.setNumber }
        let isLastSet = set.setNumber == sortedSets.last?.setNumber
        let exerciseFinishes = sortedSets.allSatisfy { $0.repsCompleted != nil }
        let repsSummary = sortedSets
            .map { $0.repsCompleted.map(String.init) ?? "–" }
            .joined(separator: " ")
        let nextSetNumber = sortedSets.first { $0.repsCompleted == nil }?.setNumber

        pendingSettleTasks[setID] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pendingSettleTasks[setID] = nil
            guard let value = capturedValue else { return }

            self?.settleFireCount += 1
            let outcome: RestOutcome = value >= targetReps ? .success : .fail

            if exerciseFinishes {
                self?.publishCompletion(
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
            let endsWorkout = exerciseFinishes && isFinalExercise
            guard !endsWorkout else {
                self?.activeRest = nil
                return
            }

            let seconds = outcome == .success ? restOnSuccess : restOnFail
            let label: String
            if exerciseFinishes {
                label = "Rest · next exercise"
            } else if let nextSetNumber {
                label = "Rest · set \(nextSetNumber) next"
            } else if isLastSet {
                label = "Rest"
            } else {
                label = "Rest"
            }

            let now = Date()
            self?.activeRest = ActiveRest(
                outcome: outcome,
                startDate: now,
                endDate: now.addingTimeInterval(TimeInterval(seconds)),
                nextUpLabel: label
            )
        }
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

    /// Total weight moved, used by the summary screen.
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
