import Testing
import SwiftData
import Foundation
@testable import SwoleData

private func makeFinishedSession(for exercise: Exercise, on date: Date, targetWeight: Double, in context: ModelContext) -> ExerciseLog {
    let session = WorkoutSession(startedAt: date, workoutType: .a, finishedAt: date)
    context.insert(session)
    let log = ExerciseLog(session: session, exercise: exercise, targetWeight: targetWeight, targetReps: 5)
    context.insert(log)
    return log
}

@Test func recentLogsOnlyIncludesFinishedSessionsOldestToNewest() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let calendar = Calendar.current
    let day0 = Date()
    let day1 = calendar.date(byAdding: .day, value: 1, to: day0)!
    let day2 = calendar.date(byAdding: .day, value: 2, to: day0)!

    _ = makeFinishedSession(for: squat, on: day1, targetWeight: 140, in: context)
    _ = makeFinishedSession(for: squat, on: day0, targetWeight: 135, in: context)

    // In-progress session for the same lift must not appear in the trend.
    let inProgress = WorkoutSession(startedAt: day2, workoutType: .a)
    context.insert(inProgress)
    context.insert(ExerciseLog(session: inProgress, exercise: squat, targetWeight: 145, targetReps: 5))

    try context.save()

    let logs = try ProgressionCalculator.recentLogs(for: squat, limit: 10, in: context)

    #expect(logs.map(\.targetWeight) == [135, 140])
}

@Test func recentLogsCapsAtLimitKeepingTheMostRecentEntries() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let calendar = Calendar.current
    for (offset, weight) in [100.0, 105, 110, 115, 120].enumerated() {
        let date = calendar.date(byAdding: .day, value: offset, to: Date())!
        _ = makeFinishedSession(for: squat, on: date, targetWeight: weight, in: context)
    }
    try context.save()

    let logs = try ProgressionCalculator.recentLogs(for: squat, limit: 3, in: context)

    #expect(logs.map(\.targetWeight) == [110, 115, 120])
}

@Test func recentLogsExcludesOtherExercises() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    let bench = Exercise(name: "Bench Press", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    context.insert(bench)

    _ = makeFinishedSession(for: squat, on: Date(), targetWeight: 135, in: context)
    _ = makeFinishedSession(for: bench, on: Date(), targetWeight: 95, in: context)
    try context.save()

    let logs = try ProgressionCalculator.recentLogs(for: squat, limit: 10, in: context)

    #expect(logs.count == 1)
    #expect(logs.first?.targetWeight == 135)
}

@Test func previousLogFindsTheMostRecentFinishedLogBeforeTheGivenOne() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let calendar = Calendar.current
    let day0 = Date()
    let day1 = calendar.date(byAdding: .day, value: 1, to: day0)!

    let older = makeFinishedSession(for: squat, on: day0, targetWeight: 130, in: context)
    let newer = makeFinishedSession(for: squat, on: day1, targetWeight: 135, in: context)
    try context.save()

    let previous = try ProgressionCalculator.previousLog(for: squat, before: newer)

    #expect(previous?.persistentModelID == older.persistentModelID)
}

@Test func previousLogIsNilWhenNoEarlierFinishedLogExists() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let onlyLog = makeFinishedSession(for: squat, on: Date(), targetWeight: 135, in: context)
    try context.save()

    let previous = try ProgressionCalculator.previousLog(for: squat, before: onlyLog)

    #expect(previous == nil)
}

@Test func previousLogIgnoresInProgressSessions() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let calendar = Calendar.current
    let day0 = Date()
    let day1 = calendar.date(byAdding: .day, value: 1, to: day0)!
    let day2 = calendar.date(byAdding: .day, value: 2, to: day0)!

    let finished = makeFinishedSession(for: squat, on: day0, targetWeight: 130, in: context)

    let unfinishedSession = WorkoutSession(startedAt: day1, workoutType: .a)
    context.insert(unfinishedSession)
    context.insert(ExerciseLog(session: unfinishedSession, exercise: squat, targetWeight: 135, targetReps: 5))

    let current = makeFinishedSession(for: squat, on: day2, targetWeight: 140, in: context)
    try context.save()

    let previous = try ProgressionCalculator.previousLog(for: squat, before: current)

    #expect(previous?.persistentModelID == finished.persistentModelID)
}
