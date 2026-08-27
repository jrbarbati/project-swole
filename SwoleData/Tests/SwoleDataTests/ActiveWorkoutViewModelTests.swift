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

@Test func tapSchedulesSuccessRestAfterSettlingOnTargetValue() async throws {
    let (log, config) = try makeFixture()
    let model = ActiveWorkoutViewModel(settleDelay: .milliseconds(20))
    let set = log.sets.sorted { $0.setNumber < $1.setNumber }[0]

    model.tap(set: set, in: log, isLastSet: false, isFinalExercise: false, config: config)
    #expect(set.repsCompleted == 5)
    #expect(model.activeRest == nil)

    try await Task.sleep(for: .milliseconds(100))

    #expect(model.activeRest?.outcome == .success)
}

@Test func rapidCorrectionTapsOnlyFireOnceUsingTheFinalSettledValue() async throws {
    let (log, config) = try makeFixture()
    let model = ActiveWorkoutViewModel(settleDelay: .milliseconds(40))
    let set = log.sets.sorted { $0.setNumber < $1.setNumber }[0]

    model.tap(set: set, in: log, isLastSet: false, isFinalExercise: false, config: config) // -> 5
    model.tap(set: set, in: log, isLastSet: false, isFinalExercise: false, config: config) // -> 4
    model.tap(set: set, in: log, isLastSet: false, isFinalExercise: false, config: config) // -> 3

    #expect(set.repsCompleted == 3)
    #expect(model.activeRest == nil)

    try await Task.sleep(for: .milliseconds(120))

    #expect(model.activeRest?.outcome == .fail)
}

@Test func cyclingBackToNotStartedBeforeSettlingFiresNoTimer() async throws {
    let (log, config) = try makeFixture(target: 1)
    let model = ActiveWorkoutViewModel(settleDelay: .milliseconds(20))
    let set = log.sets.sorted { $0.setNumber < $1.setNumber }[0]

    model.tap(set: set, in: log, isLastSet: false, isFinalExercise: false, config: config) // -> 1
    model.tap(set: set, in: log, isLastSet: false, isFinalExercise: false, config: config) // -> 0
    model.tap(set: set, in: log, isLastSet: false, isFinalExercise: false, config: config) // -> nil

    #expect(set.repsCompleted == nil)

    try await Task.sleep(for: .milliseconds(100))

    #expect(model.activeRest == nil)
    #expect(model.transitionPrompt == nil)
}

@Test func tappingTheLastSetShowsTransitionPromptInsteadOfARestTimer() async throws {
    let (log, config) = try makeFixture()
    let model = ActiveWorkoutViewModel(settleDelay: .milliseconds(20))
    let set = log.sets.sorted { $0.setNumber < $1.setNumber }.last!

    model.tap(set: set, in: log, isLastSet: true, isFinalExercise: false, config: config)

    try await Task.sleep(for: .milliseconds(100))

    #expect(model.activeRest == nil)
    #expect(model.transitionPrompt?.exerciseName == "Squat")
    #expect(model.transitionPrompt?.isFinalExercise == false)
}

@Test func dismissTransitionPromptClearsIt() async throws {
    let (log, config) = try makeFixture()
    let model = ActiveWorkoutViewModel(settleDelay: .milliseconds(20))
    let set = log.sets.sorted { $0.setNumber < $1.setNumber }.last!

    model.tap(set: set, in: log, isLastSet: true, isFinalExercise: true, config: config)
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.transitionPrompt != nil)

    model.dismissTransitionPrompt()
    #expect(model.transitionPrompt == nil)
}
