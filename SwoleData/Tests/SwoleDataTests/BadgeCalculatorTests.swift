import Testing
import SwiftData
import Foundation
@testable import SwoleData

@Test func totalVolumeTierAtIndexReturnsFixedPrefixInLb() {
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 0, unit: .lb) == 2000)
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 4, unit: .lb) == 20000)
}

@Test func totalVolumeTierAtIndexStepsByTenThousandPastThePrefixInLb() {
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 5, unit: .lb) == 30000)
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 6, unit: .lb) == 40000)
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 15, unit: .lb) == 130000)
}

@Test func totalVolumeTierAtIndexUsesTheRoundKgLadder() {
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 0, unit: .kg) == 1000)
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 4, unit: .kg) == 10000)
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 5, unit: .kg) == 15000)
}

@Test func totalVolumeIndicesReachingReturnsEarnedTiersPlusExactlyOneNext() {
    let result = BadgeCalculator.totalVolumeIndices(reaching: 12000, unit: .lb)
    #expect(result.earned == [0, 1, 2])
    #expect(result.next == 3)
}

@Test func totalVolumeIndicesReachingHandlesValuesFarPastTheFixedPrefix() {
    let result = BadgeCalculator.totalVolumeIndices(reaching: 45000, unit: .lb)
    #expect(result.earned == [0, 1, 2, 3, 4, 5, 6])
    #expect(result.next == 7)
}

@Test func totalVolumeIndicesReachingZeroEarnsNothing() {
    let result = BadgeCalculator.totalVolumeIndices(reaching: 0, unit: .lb)
    #expect(result.earned.isEmpty)
    #expect(result.next == 0)
}

@discardableResult
private func insertFinishedSession(
    exercise: Exercise,
    weight: Double,
    reps: Int,
    sets: Int,
    startedAt: Date,
    context: ModelContext
) -> WorkoutSession {
    let session = WorkoutSession(startedAt: startedAt, workoutType: .a, finishedAt: startedAt.addingTimeInterval(40 * 60))
    context.insert(session)
    let log = ExerciseLog(session: session, exercise: exercise, targetWeight: weight, targetReps: reps)
    context.insert(log)
    for n in 1...sets {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: reps))
    }
    return session
}

@Test func allBadgesShowsAllExerciseVolumeTiersLockedWithNoSessions() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    try context.save()

    let badges = try BadgeCalculator.allBadges(unit: .lb, in: context)

    let squatBadges = badges.filter {
        guard case .exerciseVolume(let name) = $0.category else { return false }
        return name == "Squat"
    }
    #expect(squatBadges.count == 6)
    #expect(squatBadges.allSatisfy { !$0.isUnlocked })
}

@Test func allBadgesUnlocksExerciseVolumeTiersReachedByCumulativeVolume() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    // 5 sets x 5 reps x 225 lb = 5625 — crosses 1000 and 5000, not 10000.
    insertFinishedSession(exercise: squat, weight: 225, reps: 5, sets: 5, startedAt: .now, context: context)
    try context.save()

    let badges = try BadgeCalculator.allBadges(unit: .lb, in: context)
    let squatBadges = badges.filter {
        guard case .exerciseVolume(let name) = $0.category else { return false }
        return name == "Squat"
    }

    #expect(squatBadges.filter(\.isUnlocked).map(\.progressTarget).sorted() == [1000, 5000])
    #expect(squatBadges.filter { !$0.isUnlocked }.map(\.progressTarget).sorted() == [10000, 25000, 50000, 100000])
}

@Test func allBadgesUsesTheKgLadderWhenUnitIsKg() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    // 5x5x80 lb = 2000 lb ≈ 907 kg — crosses the 500 kg tier, not 2500.
    insertFinishedSession(exercise: squat, weight: 80, reps: 5, sets: 5, startedAt: .now, context: context)
    try context.save()

    let badges = try BadgeCalculator.allBadges(unit: .kg, in: context)
    let squatBadges = badges.filter {
        guard case .exerciseVolume(let name) = $0.category else { return false }
        return name == "Squat"
    }

    #expect(squatBadges.filter(\.isUnlocked).map(\.progressTarget) == [500])
}

@Test func allBadgesTotalVolumeShowsEarnedTiersPlusExactlyOneNext() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    let bench = Exercise(name: "Bench Press", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    context.insert(bench)
    // 2500 (squat) + 2500 (bench) = 5000 lb total.
    insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 5, startedAt: .now, context: context)
    insertFinishedSession(exercise: bench, weight: 100, reps: 5, sets: 5, startedAt: .now, context: context)
    try context.save()

    let badges = try BadgeCalculator.allBadges(unit: .lb, in: context)
    let totalBadges = badges.filter { $0.category == .totalVolume }

    #expect(totalBadges.filter(\.isUnlocked).map(\.progressTarget).sorted() == [2000, 5000])
    #expect(totalBadges.filter { !$0.isUnlocked }.map(\.progressTarget) == [10000])
}

@Test func allBadgesWorkoutCountAndStreakReflectFinishedSessionHistory() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let now = Date()
    for offset in [0, 1, 2] {
        insertFinishedSession(exercise: squat, weight: 45, reps: 5, sets: 5, startedAt: now.addingTimeInterval(Double(offset) * 3600), context: context)
    }
    try context.save()

    let badges = try BadgeCalculator.allBadges(unit: .lb, in: context, now: now)

    let workoutCountBadges = badges.filter { $0.category == .workoutCount }
    let streakBadges = badges.filter { $0.category == .streak }
    #expect(workoutCountBadges.count == 6)
    #expect(streakBadges.count == 4)
    #expect(workoutCountBadges.allSatisfy { !$0.isUnlocked }) // 3 workouts, smallest tier is 10
    #expect(streakBadges.allSatisfy { !$0.isUnlocked }) // 1 qualifying week, smallest tier is 4
}

@Test func allBadgesStreakBadgeUnlocksAndRecordsTheCrossingWeekAfterTheStreakBreaks() throws {
    let context = try makeInMemoryContext()
    let calendar = Calendar.current
    let now = Date()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    // A 4-week qualifying run (3+ sessions/week) that ends well before `now`,
    // so the CURRENT streak is 0 while the LONGEST streak is 4. If the badge
    // were built from `currentWeeks` instead of `longestWeeks`, the 4-week
    // badge would incorrectly show as locked.
    var fourthWeekLastSessionDate: Date!
    for weeksAgo in [10, 9, 8, 7] {
        let weekStart = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: now)!
        for offset in [0, 1, 2] {
            let date = weekStart.addingTimeInterval(Double(offset) * 3600)
            insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: date, context: context)
            if weeksAgo == 7 { fourthWeekLastSessionDate = date }
        }
    }
    try context.save()

    let badges = try BadgeCalculator.allBadges(unit: .lb, in: context, now: now, calendar: calendar)
    let streak4 = badges.first { $0.category == .streak && $0.progressTarget == 4 }

    #expect(streak4?.isUnlocked == true)
    // Also guards against the unlock-dates dict being keyed by loop index
    // (0) instead of tier value (4): a wrong key would read back `nil` here
    // instead of the date the run actually reached length 4. Streak dates
    // record the qualifying week's latest session `startedAt` (not
    // `finishedAt`, unlike the volume/count paths).
    #expect(streak4?.unlockedAt == fourthWeekLastSessionDate)
}

@Test func allBadgesExerciseVolumeUnlockDateIsTheMiddleSessionThatActuallyCrossedTheTier() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let base = Date()
    let firstDate = base
    let crossingDate = base.addingTimeInterval(86400)
    let lastDate = base.addingTimeInterval(2 * 86400)

    // First session: 400 lb (cumulative 400, tier 1000 not yet crossed).
    insertFinishedSession(exercise: squat, weight: 400, reps: 1, sets: 1, startedAt: firstDate, context: context)
    // Middle session: 700 lb (cumulative 1100, crosses the 1000 tier here).
    insertFinishedSession(exercise: squat, weight: 700, reps: 1, sets: 1, startedAt: crossingDate, context: context)
    // Last session: 500 lb (cumulative 1600, no new tier crossed).
    insertFinishedSession(exercise: squat, weight: 500, reps: 1, sets: 1, startedAt: lastDate, context: context)
    try context.save()

    let badges = try BadgeCalculator.allBadges(unit: .lb, in: context)
    let tier1000 = badges.first {
        guard case .exerciseVolume(let name) = $0.category else { return false }
        return name == "Squat" && $0.progressTarget == 1000
    }

    let expectedUnlockedAt = crossingDate.addingTimeInterval(40 * 60)
    #expect(tier1000?.unlockedAt == expectedUnlockedAt)
    #expect(tier1000?.unlockedAt != firstDate.addingTimeInterval(40 * 60))
    #expect(tier1000?.unlockedAt != lastDate.addingTimeInterval(40 * 60))
}

@Test func allBadgesRecordsTheUnlockDateAsTheSessionThatCrossedTheTier() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let crossingDate = Date()
    insertFinishedSession(exercise: squat, weight: 225, reps: 5, sets: 5, startedAt: crossingDate, context: context)
    try context.save()

    let badges = try BadgeCalculator.allBadges(unit: .lb, in: context)
    let tier1000 = badges.first {
        guard case .exerciseVolume(let name) = $0.category else { return false }
        return name == "Squat" && $0.progressTarget == 1000
    }

    #expect(tier1000?.unlockedAt == crossingDate.addingTimeInterval(40 * 60))
}
