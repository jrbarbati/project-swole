import Testing
import SwiftData
import Foundation
@testable import SwoleData

@discardableResult
private func insertFinishedSession(
    exercise: Exercise,
    weight: Double,
    reps: Int,
    sets: Int,
    startedAt: Date,
    finishedAt: Date? = nil,
    context: ModelContext
) -> WorkoutSession {
    let session = WorkoutSession(
        startedAt: startedAt,
        workoutType: .a,
        finishedAt: finishedAt ?? startedAt.addingTimeInterval(40 * 60)
    )
    context.insert(session)

    let log = ExerciseLog(session: session, exercise: exercise, targetWeight: weight, targetReps: reps)
    context.insert(log)
    for n in 1...sets {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: reps))
    }

    return session
}

@Test func totalsWithNoSessionsReturnsZero() throws {
    let context = try makeInMemoryContext()

    let totals = try StatsCalculator.totals(range: .all, in: context)

    #expect(totals.workoutCount == 0)
    #expect(totals.totalVolume == 0)
    #expect(totals.averageDuration == 0)
}

@Test func totalsCountsFinishedSessionsWithinRange() throws {
    let context = try makeInMemoryContext()
    let now = Date()

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    // 2 days ago: finished 40 min later, 5 sets x 5 reps x 100 lb = 2500 volume.
    let started = Calendar.current.date(byAdding: .day, value: -2, to: now)!
    let finished = Calendar.current.date(byAdding: .minute, value: 40, to: started)!
    let session = WorkoutSession(startedAt: started, workoutType: .a, finishedAt: finished)
    context.insert(session)

    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 100, targetReps: 5)
    context.insert(log)
    for n in 1...5 {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: 5))
    }
    try context.save()

    let totals = try StatsCalculator.totals(range: .all, in: context, now: now)

    #expect(totals.workoutCount == 1)
    #expect(totals.totalVolume == 2500)
    #expect(totals.averageDuration == 40 * 60)
}

@Test func totalsExcludesSessionsOutsideRange() throws {
    let context = try makeInMemoryContext()
    let now = Date()

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    // 40 days ago: outside the 4-week range.
    let started = Calendar.current.date(byAdding: .day, value: -40, to: now)!
    let finished = Calendar.current.date(byAdding: .minute, value: 40, to: started)!
    let session = WorkoutSession(startedAt: started, workoutType: .a, finishedAt: finished)
    context.insert(session)
    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 100, targetReps: 5)
    context.insert(log)
    for n in 1...5 {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: 5))
    }
    try context.save()

    let totals = try StatsCalculator.totals(range: .fourWeeks, in: context, now: now)

    #expect(totals.workoutCount == 0)
    #expect(totals.totalVolume == 0)
}

@Test func totalsExcludesUnfinishedSessions() throws {
    let context = try makeInMemoryContext()
    let session = WorkoutSession(startedAt: Date(), workoutType: .a)
    context.insert(session)
    try context.save()

    let totals = try StatsCalculator.totals(range: .all, in: context)

    #expect(totals.workoutCount == 0)
}

// MARK: - weeklyVolume

@Test func weeklyVolumeWithNoSessionsReturnsEmpty() throws {
    let context = try makeInMemoryContext()

    let points = try StatsCalculator.weeklyVolume(range: .all, in: context)

    #expect(points.isEmpty)
}

@Test func weeklyVolumeBucketsSessionsInTheSameWeekTogether() throws {
    let context = try makeInMemoryContext()
    let calendar = Calendar.current
    let now = Date()
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    // Two sessions on day 1 and day 2 of the same calendar week: 1000 + 500 volume.
    let firstDate = calendar.date(byAdding: .hour, value: 25, to: weekStart)!
    let secondDate = calendar.date(byAdding: .hour, value: 49, to: weekStart)!
    insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 2, startedAt: firstDate, context: context)
    insertFinishedSession(exercise: squat, weight: 50, reps: 5, sets: 2, startedAt: secondDate, context: context)
    try context.save()

    let points = try StatsCalculator.weeklyVolume(range: .all, in: context, now: now)

    #expect(points.count == 1)
    #expect(points.first?.volume == 1500)
}

@Test func weeklyVolumeSeparatesDifferentWeeks() throws {
    let context = try makeInMemoryContext()
    let calendar = Calendar.current
    let now = Date()

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: now, context: context)
    let lastWeek = calendar.date(byAdding: .day, value: -14, to: now)!
    insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: lastWeek, context: context)
    try context.save()

    let points = try StatsCalculator.weeklyVolume(range: .all, in: context, now: now)

    #expect(points.count == 2)
}

// MARK: - streaks

@Test func streaksWithNoSessionsReturnsZero() throws {
    let context = try makeInMemoryContext()

    let streak = try StatsCalculator.streaks(in: context)

    #expect(streak.currentWeeks == 0)
    #expect(streak.longestWeeks == 0)
}

@Test func streaksRequireAtLeastThreeWorkoutsInAWeekToCount() throws {
    let context = try makeInMemoryContext()
    let now = Date()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: now, context: context)
    insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: now.addingTimeInterval(3600), context: context)
    try context.save()

    let streak = try StatsCalculator.streaks(in: context, now: now)

    #expect(streak.currentWeeks == 0)
    #expect(streak.longestWeeks == 0)
}

@Test func streaksCountsAWeekWithThreeWorkoutsAsCurrentStreakOfOne() throws {
    let context = try makeInMemoryContext()
    let calendar = Calendar.current
    let now = Date()
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    for offset in [0, 1, 2] {
        insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: weekStart.addingTimeInterval(Double(offset) * 3600), context: context)
    }
    try context.save()

    let streak = try StatsCalculator.streaks(in: context, now: now)

    #expect(streak.currentWeeks == 1)
    #expect(streak.longestWeeks == 1)
}

@Test func streaksContinueFromLastWeekWhenThisWeekIsEmptySoFar() throws {
    let context = try makeInMemoryContext()
    let calendar = Calendar.current
    let now = Date()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let lastWeek = calendar.date(byAdding: .day, value: -7, to: now)!
    let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: lastWeek)?.start ?? lastWeek
    for offset in [0, 1, 2] {
        insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: lastWeekStart.addingTimeInterval(Double(offset) * 3600), context: context)
    }
    try context.save()

    let streak = try StatsCalculator.streaks(in: context, now: now)

    #expect(streak.currentWeeks == 1)
}

@Test func streaksBreakAfterAGapOfMoreThanOneWeek() throws {
    let context = try makeInMemoryContext()
    let calendar = Calendar.current
    let now = Date()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let threeWeeksAgo = calendar.date(byAdding: .day, value: -21, to: now)!
    let threeWeeksAgoStart = calendar.dateInterval(of: .weekOfYear, for: threeWeeksAgo)?.start ?? threeWeeksAgo
    for offset in [0, 1, 2] {
        insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: threeWeeksAgoStart.addingTimeInterval(Double(offset) * 3600), context: context)
    }
    try context.save()

    let streak = try StatsCalculator.streaks(in: context, now: now)

    #expect(streak.currentWeeks == 0)
}

@Test func streaksLongestTracksTheBestHistoricalRunEvenAfterItEnds() throws {
    let context = try makeInMemoryContext()
    let calendar = Calendar.current
    let now = Date()
    let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    for weeksAgo in [10, 11, 12] {
        let anchor = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: now)!
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
        for offset in [0, 1, 2] {
            insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: weekStart.addingTimeInterval(Double(offset) * 3600), context: context)
        }
    }
    for offset in [0, 1, 2] {
        insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: currentWeekStart.addingTimeInterval(Double(offset) * 3600), context: context)
    }
    try context.save()

    let streak = try StatsCalculator.streaks(in: context, now: now)

    #expect(streak.currentWeeks == 1)
    #expect(streak.longestWeeks == 3)
}

// MARK: - personalRecords

@Test func personalRecordsWithNoSessionsReturnsEmpty() throws {
    let context = try makeInMemoryContext()

    let records = try StatsCalculator.personalRecords(range: .all, in: context)

    #expect(records.isEmpty)
}

@Test func personalRecordsPicksTheHeaviestSuccessfulSet() throws {
    let context = try makeInMemoryContext()
    let now = Date()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let earlier = Calendar.current.date(byAdding: .day, value: -10, to: now)!
    insertFinishedSession(exercise: squat, weight: 135, reps: 5, sets: 5, startedAt: earlier, context: context)
    insertFinishedSession(exercise: squat, weight: 185, reps: 5, sets: 5, startedAt: now, context: context)
    try context.save()

    let records = try StatsCalculator.personalRecords(range: .all, in: context, now: now)

    #expect(records.count == 1)
    #expect(records.first?.weight == 185)
    #expect(records.first?.reps == 5)
}

@Test func personalRecordsIgnoresFailedSets() throws {
    let context = try makeInMemoryContext()
    let now = Date()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let earlier = Calendar.current.date(byAdding: .day, value: -10, to: now)!
    insertFinishedSession(exercise: squat, weight: 135, reps: 5, sets: 5, startedAt: earlier, context: context)
    // Missed reps on the heavier attempt — shouldn't beat the successful 135.
    let session = WorkoutSession(startedAt: now, workoutType: .a, finishedAt: now.addingTimeInterval(2400))
    context.insert(session)
    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 185, targetReps: 5)
    context.insert(log)
    for n in 1...5 {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: n == 5 ? 3 : 5))
    }
    try context.save()

    let records = try StatsCalculator.personalRecords(range: .all, in: context, now: now)

    #expect(records.first?.weight == 135)
}

@Test func personalRecordsFlagsWhetherTheRecordWasSetWithinTheSelectedRange() throws {
    let context = try makeInMemoryContext()
    let calendar = Calendar.current
    let now = Date()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let longAgo = calendar.date(byAdding: .day, value: -100, to: now)!
    insertFinishedSession(exercise: squat, weight: 135, reps: 5, sets: 5, startedAt: longAgo, context: context)
    try context.save()

    let records = try StatsCalculator.personalRecords(range: .fourWeeks, in: context, now: now)

    #expect(records.first?.isWithinRange == false)
}

// MARK: - priorSucceededMaxWeight

@Test func priorSucceededMaxWeightReturnsNilWithNoPriorFinishedSessions() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let session = WorkoutSession(startedAt: .now, workoutType: .a, finishedAt: .now)
    context.insert(session)
    try context.save()

    let result = try StatsCalculator.priorSucceededMaxWeight(for: squat, before: session, in: context)

    #expect(result == nil)
}

@Test func priorSucceededMaxWeightReturnsTheHighestPriorSuccessfulWeight() throws {
    let context = try makeInMemoryContext()
    let now = Date()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let earlier = Calendar.current.date(byAdding: .day, value: -10, to: now)!
    insertFinishedSession(exercise: squat, weight: 135, reps: 5, sets: 5, startedAt: earlier, context: context)
    insertFinishedSession(exercise: squat, weight: 185, reps: 5, sets: 5, startedAt: earlier.addingTimeInterval(3600), context: context)

    let currentSession = WorkoutSession(startedAt: now, workoutType: .a, finishedAt: now)
    context.insert(currentSession)
    try context.save()

    let result = try StatsCalculator.priorSucceededMaxWeight(for: squat, before: currentSession, in: context)

    #expect(result == 185)
}

@Test func priorSucceededMaxWeightIgnoresFailedSetsAndExcludesTheGivenSession() throws {
    let context = try makeInMemoryContext()
    let now = Date()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let earlier = Calendar.current.date(byAdding: .day, value: -10, to: now)!
    insertFinishedSession(exercise: squat, weight: 135, reps: 5, sets: 5, startedAt: earlier, context: context)

    // A failed heavier attempt in a separate finished session shouldn't count.
    let failedStart = earlier.addingTimeInterval(3600)
    let failedSession = WorkoutSession(startedAt: failedStart, workoutType: .a, finishedAt: failedStart.addingTimeInterval(2400))
    context.insert(failedSession)
    let failedLog = ExerciseLog(session: failedSession, exercise: squat, targetWeight: 225, targetReps: 5)
    context.insert(failedLog)
    for n in 1...5 {
        context.insert(SetLog(exerciseLog: failedLog, setNumber: n, repsCompleted: n == 5 ? 3 : 5))
    }

    // The session being checked "before" also has its own squat log — must be excluded from the result.
    let currentSession = WorkoutSession(startedAt: now, workoutType: .a, finishedAt: now)
    context.insert(currentSession)
    let currentLog = ExerciseLog(session: currentSession, exercise: squat, targetWeight: 300, targetReps: 5)
    context.insert(currentLog)
    for n in 1...5 {
        context.insert(SetLog(exerciseLog: currentLog, setNumber: n, repsCompleted: 5))
    }
    try context.save()

    let result = try StatsCalculator.priorSucceededMaxWeight(for: squat, before: currentSession, in: context)

    #expect(result == 135)
}

// MARK: - trendLogs

@Test func trendLogsReturnsOnlyLogsWithinRangeOldestFirst() throws {
    let context = try makeInMemoryContext()
    let calendar = Calendar.current
    let now = Date()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let outsideRange = calendar.date(byAdding: .day, value: -40, to: now)!
    let insideRangeEarlier = calendar.date(byAdding: .day, value: -10, to: now)!
    insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: outsideRange, context: context)
    insertFinishedSession(exercise: squat, weight: 130, reps: 5, sets: 1, startedAt: insideRangeEarlier, context: context)
    insertFinishedSession(exercise: squat, weight: 135, reps: 5, sets: 1, startedAt: now, context: context)
    try context.save()

    let logs = try StatsCalculator.trendLogs(for: squat, range: .fourWeeks, in: context, now: now)

    #expect(logs.map(\.targetWeight) == [130, 135])
}
