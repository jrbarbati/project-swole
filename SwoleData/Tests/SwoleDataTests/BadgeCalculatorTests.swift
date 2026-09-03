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

    #expect(badges.filter { $0.category == .workoutCount }.allSatisfy { !$0.isUnlocked }) // 3 workouts, smallest tier is 10
    #expect(badges.filter { $0.category == .streak }.allSatisfy { !$0.isUnlocked }) // 1 qualifying week, smallest tier is 4
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
