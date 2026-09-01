import Testing
import SwiftData
import Foundation
@testable import SwoleData

private func makeFixture(target: Int = 5, restOnSuccess: Int = 90, restOnFail: Int = 180) throws -> (log: ExerciseLog, config: UserExerciseConfig) {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = UserExerciseConfig(
        exercise: squat, startingWeight: 45, weightIncrement: 5,
        setCount: 5, repsPerSet: target, deloadThreshold: 3, deloadPercentage: 0.10,
        restSecondsOnSuccess: restOnSuccess, restSecondsOnFail: restOnFail
    )
    context.insert(config)
    let session = WorkoutSession(startedAt: .now, workoutType: .a)
    context.insert(session)
    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 135, targetReps: target, order: 0)
    context.insert(log)
    for n in 1...5 {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: nil))
    }
    try context.save()
    return (log, config)
}

@Test @MainActor func tapSchedulesSuccessRestAfterSettlingOnTargetValue() async throws {
    let (log, config) = try makeFixture()
    let model = ActiveWorkoutViewModel(settleDelay: .milliseconds(20))
    let set = log.sets.sorted { $0.setNumber < $1.setNumber }[0]

    model.tap(set: set, in: log, isFinalExercise: false, config: config)
    #expect(set.repsCompleted == 5)
    #expect(model.activeRest == nil)

    try await Task.sleep(for: .milliseconds(100))

    #expect(model.activeRest?.outcome == .success)
}

@Test @MainActor func rapidCorrectionTapsOnlyFireOnceUsingTheFinalSettledValue() async throws {
    let (log, config) = try makeFixture()
    let model = ActiveWorkoutViewModel(settleDelay: .milliseconds(40))
    let set = log.sets.sorted { $0.setNumber < $1.setNumber }[0]

    model.tap(set: set, in: log, isFinalExercise: false, config: config) // -> 5
    model.tap(set: set, in: log, isFinalExercise: false, config: config) // -> 4
    model.tap(set: set, in: log, isFinalExercise: false, config: config) // -> 3

    #expect(set.repsCompleted == 3)
    #expect(model.activeRest == nil)

    try await Task.sleep(for: .milliseconds(120))

    #expect(model.activeRest?.outcome == .fail)
    #expect(model.settleFireCount == 1)
}

@Test @MainActor func cyclingBackToNotStartedBeforeSettlingFiresNoTimer() async throws {
    let (log, config) = try makeFixture(target: 1)
    let model = ActiveWorkoutViewModel(settleDelay: .milliseconds(20))
    let set = log.sets.sorted { $0.setNumber < $1.setNumber }[0]

    model.tap(set: set, in: log, isFinalExercise: false, config: config) // -> 1
    model.tap(set: set, in: log, isFinalExercise: false, config: config) // -> 0
    model.tap(set: set, in: log, isFinalExercise: false, config: config) // -> nil

    #expect(set.repsCompleted == nil)

    try await Task.sleep(for: .milliseconds(100))

    #expect(model.activeRest == nil)
    #expect(model.completion == nil)
}

@Test @MainActor func settlingTheLastSetOfAnExerciseShowsCompletionInsteadOfARestTimer() async throws {
    let (log, config) = try makeFixture()
    let model = ActiveWorkoutViewModel(settleDelay: .milliseconds(20))
    let sets = log.sets.sorted { $0.setNumber < $1.setNumber }
    for set in sets.dropLast() {
        set.repsCompleted = 5
    }

    model.tap(set: sets.last!, in: log, isFinalExercise: false, config: config)

    try await Task.sleep(for: .milliseconds(100))

    #expect(model.completion?.exerciseName == "Squat")
    #expect(model.completion?.isFinalExercise == false)
    #expect(model.activeRest != nil)
}

@Test @MainActor func settlingTheLastSetOfTheFinalExerciseStartsNoRest() async throws {
    let (log, config) = try makeFixture()
    let model = ActiveWorkoutViewModel(settleDelay: .milliseconds(20))
    let sets = log.sets.sorted { $0.setNumber < $1.setNumber }
    for set in sets.dropLast() {
        set.repsCompleted = 5
    }

    model.tap(set: sets.last!, in: log, isFinalExercise: true, config: config)

    try await Task.sleep(for: .milliseconds(100))

    #expect(model.completion?.isFinalExercise == true)
    #expect(model.activeRest == nil)
}

@Test @MainActor func dismissCompletionClearsIt() async throws {
    let (log, config) = try makeFixture()
    let model = ActiveWorkoutViewModel(settleDelay: .milliseconds(20))
    let sets = log.sets.sorted { $0.setNumber < $1.setNumber }
    for set in sets.dropLast() {
        set.repsCompleted = 5
    }

    model.tap(set: sets.last!, in: log, isFinalExercise: true, config: config)
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.completion != nil)

    model.dismissCompletion()
    #expect(model.completion == nil)
}

@Test @MainActor func restoreSetsActiveRestFromPersistedWindow() throws {
    let model = ActiveWorkoutViewModel()
    let start = Date.now.addingTimeInterval(-30)
    let end = Date.now.addingTimeInterval(60)

    model.restore(startDate: start, endDate: end, label: "Rest · set 3 next")

    #expect(model.activeRest?.startDate == start)
    #expect(model.activeRest?.endDate == end)
    #expect(model.activeRest?.nextUpLabel == "Rest · set 3 next")
    #expect(model.activeRest?.remaining(at: .now) ?? 0 > 0)
}
