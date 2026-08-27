import Testing
import SwiftData
import Foundation
@testable import SwoleData

private func makeSeededContext() throws -> ModelContext {
    let context = try makeInMemoryContext()
    _ = try StandardSeed.seed(in: context)
    return context
}

@Test func activeSessionIsNilWhenNoneExists() throws {
    let context = try makeSeededContext()
    #expect(try WorkoutSessionService.activeSession(in: context) == nil)
}

@Test func startWorkoutCreatesExerciseLogsInTemplateOrderWithComputedWeights() throws {
    let context = try makeSeededContext()

    let session = try WorkoutSessionService.startWorkout(in: context)

    #expect(session.workoutType == .a)
    #expect(session.finishedAt == nil)

    let logs = session.exerciseLogs.sorted { $0.order < $1.order }
    #expect(logs.map { $0.exercise?.name } == ["Squat", "Bench Press", "Barbell Row"])
    #expect(logs.map(\.order) == [0, 1, 2])

    let squatLog = logs[0]
    #expect(squatLog.targetWeight == 45)
    #expect(squatLog.targetReps == 5)
    #expect(squatLog.sets.count == 5)
    #expect(squatLog.sets.allSatisfy { $0.repsCompleted == nil })

    #expect(try WorkoutSessionService.activeSession(in: context) === session)
}

@Test func startWorkoutThrowsWhenUserSettingsAreMissing() throws {
    let context = try makeInMemoryContext()
    #expect(throws: WorkoutSessionServiceError.self) {
        try WorkoutSessionService.startWorkout(in: context)
    }
}

@Test func finishWorkoutCoercesUnsetRepsToZeroLocksSessionAndUpdatesSettings() throws {
    let context = try makeSeededContext()
    let session = try WorkoutSessionService.startWorkout(in: context)

    try WorkoutSessionService.finishWorkout(session, in: context)

    #expect(session.finishedAt != nil)
    #expect(session.exerciseLogs.flatMap(\.sets).allSatisfy { $0.repsCompleted == 0 })

    let settings = try context.fetch(FetchDescriptor<UserSettings>()).first
    #expect(settings?.lastCompletedWorkoutType == .a)
    #expect(try WorkoutSessionService.activeSession(in: context) == nil)
}

@Test func cancelWorkoutDeletesSessionAndLeavesLastCompletedWorkoutTypeUntouched() throws {
    let context = try makeSeededContext()
    let session = try WorkoutSessionService.startWorkout(in: context)

    try WorkoutSessionService.cancelWorkout(session, in: context)

    #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<ExerciseLog>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)

    let settings = try context.fetch(FetchDescriptor<UserSettings>()).first
    #expect(settings?.lastCompletedWorkoutType == nil)
}
