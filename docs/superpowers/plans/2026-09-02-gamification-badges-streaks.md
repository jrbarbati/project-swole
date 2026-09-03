# Gamification: badges + streaks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add computed (no new persisted model) achievement badges — per-exercise volume, total volume, workout count, and streak-length — plus redefine the existing week-streak stat to require 3+ workouts/week.

**Architecture:** A new pure `BadgeCalculator` enum in the `SwoleData` package (same style as `StatsCalculator`/`XPCalculator`) computes badge state on demand from existing `WorkoutSession`/`ExerciseLog` data — no schema change. `WorkoutSessionService.finishWorkout` diffs badge state before/after the finishing session (same trick already used for PR detection) to report newly-unlocked badges in `XPAward`. `StatsCalculator.streaks` is redefined so a week only counts with ≥3 finished sessions.

**Tech Stack:** Swift, SwiftData, SwiftUI, Swift Testing (`@Test`/`#expect`), XCUITest.

**Spec:** `docs/superpowers/specs/2026-09-02-gamification-badges-streaks-design.md`

## Global Constraints

- No new `@Model` type and no `Schema.swift` change — badges are fully computed.
- Per-exercise volume tiers: lb `[1000, 5000, 10000, 25000, 50000, 100000]`; kg `[500, 2500, 5000, 10000, 25000, 50000]`.
- Total-volume tiers (open-ended): lb fixed prefix `[2000, 5000, 10000, 15000, 20000]` then +10,000/tier; kg fixed prefix `[1000, 2500, 5000, 7500, 10000]` then +5,000/tier.
- Workout-count tiers (unit-independent): `[10, 25, 50, 100, 250, 500]`.
- Streak tiers (unit-independent, weeks): `[4, 12, 26, 52]`, keyed to **longest** streak ever reached, not the current one.
- A week counts toward a streak only with ≥3 finished sessions (was ≥1) — applies to `StatsView`'s existing "week streak" card too, not just badges.
- Fixed-tier categories (exercise volume, workout count, streak) always list **every** tier, locked or not. The open-ended total-volume category lists every **earned** tier plus exactly one locked "next" tile — never the whole infinite ladder.
- Work directly on `main`, commit after each task.

---

### Task 1: Redefine `StatsCalculator.streaks` to require 3+ workouts/week

**Files:**
- Modify: `SwoleData/Sources/SwoleData/StatsCalculator.swift`
- Test: `SwoleData/Tests/SwoleDataTests/StatsCalculatorTests.swift`

**Interfaces:**
- Produces: `StatsCalculator.streaks(from sessions: [WorkoutSession], now: Date, calendar: Calendar) -> StreakInfo` (internal, no throws) — a pure extraction of the existing run-length logic, reused by `BadgeCalculator` in Task 3. Public `streaks(in:now:calendar:)` keeps its existing signature and now delegates to this.

- [ ] **Step 1: Update the existing streak tests to require 3 workouts/week**

In `StatsCalculatorTests.swift`, replace these four tests (search for `// MARK: - streaks` to find the section) with the versions below — each week that should "count" now needs 3 sessions instead of 1:

```swift
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
    let now = Date()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    for offset in [0, 1, 2] {
        insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: now.addingTimeInterval(Double(offset) * 3600), context: context)
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
    for offset in [0, 1, 2] {
        insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: lastWeek.addingTimeInterval(Double(offset) * 3600), context: context)
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
    for offset in [0, 1, 2] {
        insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: threeWeeksAgo.addingTimeInterval(Double(offset) * 3600), context: context)
    }
    try context.save()

    let streak = try StatsCalculator.streaks(in: context, now: now)

    #expect(streak.currentWeeks == 0)
}

@Test func streaksLongestTracksTheBestHistoricalRunEvenAfterItEnds() throws {
    let context = try makeInMemoryContext()
    let calendar = Calendar.current
    let now = Date()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    for weeksAgo in [10, 11, 12] {
        let weekStart = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: now)!
        for offset in [0, 1, 2] {
            insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: weekStart.addingTimeInterval(Double(offset) * 3600), context: context)
        }
    }
    for offset in [0, 1, 2] {
        insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 1, startedAt: now.addingTimeInterval(Double(offset) * 3600), context: context)
    }
    try context.save()

    let streak = try StatsCalculator.streaks(in: context, now: now)

    #expect(streak.currentWeeks == 1)
    #expect(streak.longestWeeks == 3)
}
```

The first test (`streaksRequireAtLeastThreeWorkoutsInAWeekToCount`) is new — the other four replace existing tests of nearly the same name/intent.

- [ ] **Step 2: Run the tests to verify they fail against the current implementation**

Run: `cd SwoleData && swift test --filter StatsCalculatorTests`
Expected: FAIL — `streaksRequireAtLeastThreeWorkoutsInAWeekToCount` fails because today any session counts (current implementation would report `currentWeeks == 1`, not `0`).

- [ ] **Step 3: Redefine `streaks` in `StatsCalculator.swift`**

Replace the existing `streaks(in:now:calendar:)` function with:

```swift
    static func streaks(from sessions: [WorkoutSession], now: Date, calendar: Calendar) -> StreakInfo {
        let sessionsByWeek = Dictionary(grouping: sessions) { calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start ?? $0.startedAt }
        let weekStarts = Set(sessionsByWeek.filter { $0.value.count >= 3 }.map(\.key))
        guard !weekStarts.isEmpty else { return StreakInfo(currentWeeks: 0, longestWeeks: 0) }

        let sorted = weekStarts.sorted()
        var longest = 1
        var run = 1
        for i in 1..<sorted.count {
            if calendar.date(byAdding: .day, value: 7, to: sorted[i - 1]) == sorted[i] {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
        }

        let nowWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let priorWeekStart = calendar.date(byAdding: .day, value: -7, to: nowWeekStart) ?? nowWeekStart

        var current = 0
        if weekStarts.contains(nowWeekStart) || weekStarts.contains(priorWeekStart) {
            var cursor = weekStarts.contains(nowWeekStart) ? nowWeekStart : priorWeekStart
            while weekStarts.contains(cursor) {
                current += 1
                cursor = calendar.date(byAdding: .day, value: -7, to: cursor) ?? .distantPast
            }
        }

        return StreakInfo(currentWeeks: current, longestWeeks: longest)
    }

    public static func streaks(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws -> StreakInfo {
        let sessions = try finishedSessions(in: context)
        return streaks(from: sessions, now: now, calendar: calendar)
    }
```

(The new internal `streaks(from:now:calendar:)` replaces the old public function's body; the old body's `weekStarts` line — which counted any session — is gone.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd SwoleData && swift test --filter StatsCalculatorTests`
Expected: PASS (all streak tests, plus every other `StatsCalculatorTests` test still passing).

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/StatsCalculator.swift SwoleData/Tests/SwoleDataTests/StatsCalculatorTests.swift
git commit -m "feat: require 3+ workouts/week for a streak week to count"
```

---

### Task 2: `BadgeCalculator` — types, tier tables, open-ended tier math

**Files:**
- Create: `SwoleData/Sources/SwoleData/BadgeCalculator.swift`
- Test: `SwoleData/Tests/SwoleDataTests/BadgeCalculatorTests.swift` (new file)

**Interfaces:**
- Produces: `public enum BadgeCategory: Hashable, Sendable { case exerciseVolume(exerciseName: String), totalVolume, workoutCount, streak }`; `public struct Badge: Identifiable, Equatable, Sendable { id, category, title, iconName, isUnlocked, unlockedAt, progressCurrent, progressTarget }`; `static func totalVolumeTier(atIndex: Int, unit: MeasurementUnit) -> Double`; `static func totalVolumeIndices(reaching value: Double, unit: MeasurementUnit) -> (earned: [Int], next: Int)`. These four are used by Task 3.

- [ ] **Step 1: Write the failing tests**

Create `SwoleData/Tests/SwoleDataTests/BadgeCalculatorTests.swift`:

```swift
import Testing
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd SwoleData && swift test --filter BadgeCalculatorTests`
Expected: FAIL to compile — `BadgeCalculator` doesn't exist yet.

- [ ] **Step 3: Create `BadgeCalculator.swift` with types and tier math**

```swift
import Foundation
import SwiftData

public enum BadgeCategory: Hashable, Sendable {
    case exerciseVolume(exerciseName: String)
    case totalVolume
    case workoutCount
    case streak
}

public struct Badge: Identifiable, Equatable, Sendable {
    public let id: String
    public let category: BadgeCategory
    public let title: String
    public let iconName: String
    public let isUnlocked: Bool
    public let unlockedAt: Date?
    public let progressCurrent: Double
    public let progressTarget: Double
}

public enum BadgeCalculator {

    // MARK: - Tier tables

    private static let exerciseVolumeTiersLb: [Double] = [1000, 5000, 10000, 25000, 50000, 100000]
    private static let exerciseVolumeTiersKg: [Double] = [500, 2500, 5000, 10000, 25000, 50000]

    private static let totalVolumeBaseTiersLb: [Double] = [2000, 5000, 10000, 15000, 20000]
    private static let totalVolumeStepLb: Double = 10000
    private static let totalVolumeBaseTiersKg: [Double] = [1000, 2500, 5000, 7500, 10000]
    private static let totalVolumeStepKg: Double = 5000

    static let workoutCountTiers: [Int] = [10, 25, 50, 100, 250, 500]
    static let streakWeekTiers: [Int] = [4, 12, 26, 52]

    private static func exerciseVolumeTiers(unit: MeasurementUnit) -> [Double] {
        unit == .lb ? exerciseVolumeTiersLb : exerciseVolumeTiersKg
    }

    /// Tier value at `index` (0-based) for the open-ended total-volume ladder.
    static func totalVolumeTier(atIndex index: Int, unit: MeasurementUnit) -> Double {
        let base = unit == .lb ? totalVolumeBaseTiersLb : totalVolumeBaseTiersKg
        let step = unit == .lb ? totalVolumeStepLb : totalVolumeStepKg
        if index < base.count { return base[index] }
        return base[base.count - 1] + step * Double(index - base.count + 1)
    }

    /// Every tier index whose threshold is `<= value`, plus the single next
    /// locked index — never the full infinite ladder.
    static func totalVolumeIndices(reaching value: Double, unit: MeasurementUnit) -> (earned: [Int], next: Int) {
        var earned: [Int] = []
        var index = 0
        while totalVolumeTier(atIndex: index, unit: unit) <= value {
            earned.append(index)
            index += 1
        }
        return (earned, index)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd SwoleData && swift test --filter BadgeCalculatorTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/BadgeCalculator.swift SwoleData/Tests/SwoleDataTests/BadgeCalculatorTests.swift
git commit -m "feat: add Badge types and total-volume tier math"
```

---

### Task 3: `BadgeCalculator.allBadges` — aggregates, unlock dates, full badge list

**Files:**
- Modify: `SwoleData/Sources/SwoleData/BadgeCalculator.swift`
- Test: `SwoleData/Tests/SwoleDataTests/BadgeCalculatorTests.swift`

**Interfaces:**
- Consumes: `StatsCalculator.streaks(from:now:calendar:)` (Task 1); `ExerciseLog.volume`, `WorkoutSession.exerciseLogs` (existing); `MeasurementUnit.fromLb` (existing).
- Produces: `public static func allBadges(unit: MeasurementUnit, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws -> [Badge]`. Also a private `coreBadges(unit:excluding:in:now:calendar:)` that Task 4's `newlyUnlocked` calls directly.

- [ ] **Step 1: Write the failing tests**

Append to `BadgeCalculatorTests.swift`:

```swift
import SwiftData
import Foundation

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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd SwoleData && swift test --filter BadgeCalculatorTests`
Expected: FAIL to compile — `allBadges` doesn't exist yet.

- [ ] **Step 3: Implement aggregates, unlock-date scan, and `allBadges` in `BadgeCalculator.swift`**

Append inside the `BadgeCalculator` enum (after the tier math from Task 2):

```swift
    // MARK: - Aggregates

    private static func finishedSessions(excluding sessionID: PersistentIdentifier?, in context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.finishedAt != nil && (sessionID == nil || $0.persistentModelID != sessionID) }
    }

    private static func exerciseVolumesLb(from sessions: [WorkoutSession]) -> [String: Double] {
        var result: [String: Double] = [:]
        for session in sessions {
            for log in session.exerciseLogs {
                result[log.exercise?.name ?? "", default: 0] += log.volume
            }
        }
        return result
    }

    // MARK: - Unlock dates (chronological pass)

    private struct UnlockDates {
        var exercise: [String: [Date?]] = [:]
        var totalVolume: [Int: Date] = [:]
        var workoutCount: [Date?] = Array(repeating: nil, count: BadgeCalculator.workoutCountTiers.count)
        var streak: [Int: Date] = [:]
    }

    private static func computeUnlockDates(sessions: [WorkoutSession], unit: MeasurementUnit, calendar: Calendar) -> UnlockDates {
        var dates = UnlockDates()
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        let exerciseTiers = exerciseVolumeTiers(unit: unit)

        var runningVolume: [String: Double] = [:]
        var runningTotal: Double = 0
        var runningCount = 0

        for session in sorted {
            let date = session.finishedAt ?? session.startedAt
            runningCount += 1
            for (index, tier) in workoutCountTiers.enumerated()
            where dates.workoutCount[index] == nil && runningCount >= tier {
                dates.workoutCount[index] = date
            }

            var sessionVolumeByExercise: [String: Double] = [:]
            for log in session.exerciseLogs {
                sessionVolumeByExercise[log.exercise?.name ?? "", default: 0] += log.volume
            }

            for (name, volume) in sessionVolumeByExercise {
                runningVolume[name, default: 0] += volume
                runningTotal += volume

                let convertedExerciseVolume = unit.fromLb(runningVolume[name] ?? 0)
                var exerciseDates = dates.exercise[name] ?? Array(repeating: nil, count: exerciseTiers.count)
                for (index, tier) in exerciseTiers.enumerated()
                where exerciseDates[index] == nil && convertedExerciseVolume >= tier {
                    exerciseDates[index] = date
                }
                dates.exercise[name] = exerciseDates
            }

            let convertedTotal = unit.fromLb(runningTotal)
            var index = 0
            while totalVolumeTier(atIndex: index, unit: unit) <= convertedTotal {
                if dates.totalVolume[index] == nil { dates.totalVolume[index] = date }
                index += 1
            }
        }

        let sessionsByWeek = Dictionary(grouping: sessions) { calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start ?? $0.startedAt }
        let qualifyingWeeks = sessionsByWeek.filter { $0.value.count >= 3 }
        let sortedWeeks = qualifyingWeeks.map(\.key).sorted()

        var run = 0
        var previousWeek: Date?
        for week in sortedWeeks {
            if let previousWeek, calendar.date(byAdding: .day, value: 7, to: previousWeek) == week {
                run += 1
            } else {
                run = 1
            }
            previousWeek = week
            if streakWeekTiers.contains(run), dates.streak[run] == nil {
                dates.streak[run] = qualifyingWeeks[week]?.map(\.startedAt).max() ?? week
            }
        }

        return dates
    }

    // MARK: - Badge construction

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private static func exerciseVolumeBadge(exercise: String, index: Int, unit: MeasurementUnit, current: Double, unlocked: Bool, unlockedAt: Date?) -> Badge {
        let target = exerciseVolumeTiers(unit: unit)[index]
        return Badge(
            id: "volume.\(exercise).\(index)",
            category: .exerciseVolume(exerciseName: exercise),
            title: "\(exercise) — \(formatted(target)) \(unit.rawValue) Lifted",
            iconName: "dumbbell.fill",
            isUnlocked: unlocked,
            unlockedAt: unlockedAt,
            progressCurrent: current,
            progressTarget: target
        )
    }

    private static func totalVolumeBadge(index: Int, unit: MeasurementUnit, current: Double, unlocked: Bool, unlockedAt: Date?) -> Badge {
        let target = totalVolumeTier(atIndex: index, unit: unit)
        return Badge(
            id: "totalVolume.\(index)",
            category: .totalVolume,
            title: "\(formatted(target)) \(unit.rawValue) Total Lifted",
            iconName: "scalemass.fill",
            isUnlocked: unlocked,
            unlockedAt: unlockedAt,
            progressCurrent: current,
            progressTarget: target
        )
    }

    private static func workoutCountBadge(index: Int, current: Int, unlocked: Bool, unlockedAt: Date?) -> Badge {
        let target = workoutCountTiers[index]
        return Badge(
            id: "workoutCount.\(index)",
            category: .workoutCount,
            title: "\(target) Workouts Completed",
            iconName: "checkmark.seal.fill",
            isUnlocked: unlocked,
            unlockedAt: unlockedAt,
            progressCurrent: Double(current),
            progressTarget: Double(target)
        )
    }

    private static func streakBadge(index: Int, current: Int, unlocked: Bool, unlockedAt: Date?) -> Badge {
        let target = streakWeekTiers[index]
        return Badge(
            id: "streak.\(index)",
            category: .streak,
            title: "\(target)-Week Streak",
            iconName: "flame.fill",
            isUnlocked: unlocked,
            unlockedAt: unlockedAt,
            progressCurrent: Double(current),
            progressTarget: Double(target)
        )
    }

    // MARK: - Public API

    private static func coreBadges(unit: MeasurementUnit, excluding sessionID: PersistentIdentifier?, in context: ModelContext, now: Date, calendar: Calendar) throws -> [Badge] {
        let exercises = try context.fetch(FetchDescriptor<Exercise>()).sorted { $0.name < $1.name }
        let sessions = try finishedSessions(excluding: sessionID, in: context)
        let volumesLb = exerciseVolumesLb(from: sessions)
        let totalVolumeLb = volumesLb.values.reduce(0, +)
        let workoutCount = sessions.count
        let longestStreakWeeks = StatsCalculator.streaks(from: sessions, now: now, calendar: calendar).longestWeeks
        let unlockDates = computeUnlockDates(sessions: sessions, unit: unit, calendar: calendar)

        var badges: [Badge] = []

        let exerciseTiers = exerciseVolumeTiers(unit: unit)
        for exercise in exercises {
            let currentLb = volumesLb[exercise.name] ?? 0
            let current = unit.fromLb(currentLb)
            for (index, tier) in exerciseTiers.enumerated() {
                let unlocked = current >= tier
                badges.append(exerciseVolumeBadge(
                    exercise: exercise.name, index: index, unit: unit, current: current,
                    unlocked: unlocked, unlockedAt: unlocked ? (unlockDates.exercise[exercise.name]?[index]) : nil
                ))
            }
        }

        let totalCurrent = unit.fromLb(totalVolumeLb)
        let (totalEarned, totalNext) = totalVolumeIndices(reaching: totalCurrent, unit: unit)
        for index in totalEarned {
            badges.append(totalVolumeBadge(index: index, unit: unit, current: totalCurrent, unlocked: true, unlockedAt: unlockDates.totalVolume[index]))
        }
        badges.append(totalVolumeBadge(index: totalNext, unit: unit, current: totalCurrent, unlocked: false, unlockedAt: nil))

        for (index, tier) in workoutCountTiers.enumerated() {
            let unlocked = workoutCount >= tier
            badges.append(workoutCountBadge(index: index, current: workoutCount, unlocked: unlocked, unlockedAt: unlocked ? unlockDates.workoutCount[index] : nil))
        }

        for (index, tier) in streakWeekTiers.enumerated() {
            let unlocked = longestStreakWeeks >= tier
            badges.append(streakBadge(index: index, current: longestStreakWeeks, unlocked: unlocked, unlockedAt: unlocked ? unlockDates.streak[tier] : nil))
        }

        return badges
    }

    public static func allBadges(unit: MeasurementUnit, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws -> [Badge] {
        try coreBadges(unit: unit, excluding: nil, in: context, now: now, calendar: calendar)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd SwoleData && swift test --filter BadgeCalculatorTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/BadgeCalculator.swift SwoleData/Tests/SwoleDataTests/BadgeCalculatorTests.swift
git commit -m "feat: compute the full badge list from workout history"
```

---

### Task 4: `BadgeCalculator.newlyUnlocked`

**Files:**
- Modify: `SwoleData/Sources/SwoleData/BadgeCalculator.swift`
- Test: `SwoleData/Tests/SwoleDataTests/BadgeCalculatorTests.swift`

**Interfaces:**
- Consumes: `coreBadges(unit:excluding:in:now:calendar:)` (Task 3, private — this task adds the one public caller).
- Produces: `public static func newlyUnlocked(for session: WorkoutSession, unit: MeasurementUnit, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws -> [Badge]` — used by Task 5.

- [ ] **Step 1: Write the failing tests**

Append to `BadgeCalculatorTests.swift`:

```swift
@Test func newlyUnlockedReturnsTierCrossedByThisSessionOnly() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    insertFinishedSession(exercise: squat, weight: 100, reps: 5, sets: 5, startedAt: Date().addingTimeInterval(-86400), context: context)
    try context.save()

    let session = insertFinishedSession(exercise: squat, weight: 150, reps: 5, sets: 5, startedAt: .now, context: context)
    try context.save()

    let newBadges = try BadgeCalculator.newlyUnlocked(for: session, unit: .lb, in: context)

    let crossedTargets = newBadges.compactMap { badge -> Double? in
        guard case .exerciseVolume(let name) = badge.category, name == "Squat" else { return nil }
        return badge.progressTarget
    }
    #expect(crossedTargets == [5000])
}

@Test func newlyUnlockedReturnsNothingWhenNoTierIsCrossed() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    insertFinishedSession(exercise: squat, weight: 200, reps: 5, sets: 5, startedAt: Date().addingTimeInterval(-86400), context: context)
    try context.save()
    let session = insertFinishedSession(exercise: squat, weight: 5, reps: 1, sets: 1, startedAt: .now, context: context)
    try context.save()

    let newBadges = try BadgeCalculator.newlyUnlocked(for: session, unit: .lb, in: context)

    #expect(newBadges.isEmpty)
}

@Test func newlyUnlockedNeverReturnsATierAlreadyEarnedBeforeThisSession() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    insertFinishedSession(exercise: squat, weight: 1000, reps: 5, sets: 5, startedAt: Date().addingTimeInterval(-86400), context: context)
    try context.save()
    let session = insertFinishedSession(exercise: squat, weight: 10, reps: 1, sets: 1, startedAt: .now, context: context)
    try context.save()

    let newBadges = try BadgeCalculator.newlyUnlocked(for: session, unit: .lb, in: context)

    #expect(newBadges.isEmpty)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd SwoleData && swift test --filter BadgeCalculatorTests`
Expected: FAIL to compile — `newlyUnlocked` doesn't exist yet.

- [ ] **Step 3: Implement `newlyUnlocked`**

Add after `allBadges` in `BadgeCalculator.swift`:

```swift
    public static func newlyUnlocked(for session: WorkoutSession, unit: MeasurementUnit, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws -> [Badge] {
        let after = try coreBadges(unit: unit, excluding: nil, in: context, now: now, calendar: calendar)
        let before = try coreBadges(unit: unit, excluding: session.persistentModelID, in: context, now: now, calendar: calendar)
        let beforeUnlockedIDs = Set(before.filter(\.isUnlocked).map(\.id))
        return after.filter { $0.isUnlocked && !beforeUnlockedIDs.contains($0.id) }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd SwoleData && swift test --filter BadgeCalculatorTests`
Expected: PASS — run the full `SwoleData` suite too (`swift test`) to confirm nothing else regressed.

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/BadgeCalculator.swift SwoleData/Tests/SwoleDataTests/BadgeCalculatorTests.swift
git commit -m "feat: detect badges newly unlocked by finishing a session"
```

---

### Task 5: Wire badges into `WorkoutSessionService.finishWorkout`

**Files:**
- Modify: `SwoleData/Sources/SwoleData/WorkoutSessionService.swift`
- Test: `SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift`

**Interfaces:**
- Consumes: `BadgeCalculator.newlyUnlocked(for:unit:in:)` (Task 4).
- Produces: `XPAward.newBadges: [Badge]` — consumed by `XPRevealView` in Task 6.

- [ ] **Step 1: Write the failing tests**

Append to `WorkoutSessionServiceTests.swift`:

```swift
@Test func finishWorkoutIncludesNewlyUnlockedBadgesInTheAward() throws {
    let context = try makeSeededContext()
    let session = try WorkoutSessionService.startWorkout(in: context)

    for log in session.exerciseLogs {
        for set in log.sets {
            set.repsCompleted = log.targetReps
        }
    }

    let award = try WorkoutSessionService.finishWorkout(session, in: context)

    let squatBadge = award.newBadges.first {
        guard case .exerciseVolume(let name) = $0.category else { return false }
        return name == "Squat" && $0.progressTarget == 1000
    }
    #expect(squatBadge != nil)
}

@Test func finishWorkoutReturnsNoNewBadgesWhenNoTierIsCrossed() throws {
    let context = try makeSeededContext()
    let session = try WorkoutSessionService.startWorkout(in: context)

    let award = try WorkoutSessionService.finishWorkout(session, in: context)

    #expect(award.newBadges.isEmpty)
}
```

(`makeSeededContext` and `startWorkout` are the existing helpers already used by this file.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd SwoleData && swift test --filter WorkoutSessionServiceTests`
Expected: FAIL to compile — `XPAward` has no `newBadges` member yet.

- [ ] **Step 3: Add `newBadges` to `XPAward` and compute it in `finishWorkout`**

In `WorkoutSessionService.swift`, add the field to `XPAward`:

```swift
public struct XPAward: Equatable {
    public let base: Int
    public let prCount: Int
    public let prBonus: Int
    public let perfectBonus: Int
    public let weeklyBonus: Int
    public let xpBefore: Int
    public let xpAfter: Int
    public let newBadges: [Badge]
    public var total: Int { base + prBonus + perfectBonus + weeklyBonus }
}
```

Update `finishWorkout` to compute badges and pass them through:

```swift
    @discardableResult
    public static func finishWorkout(_ session: WorkoutSession, in context: ModelContext) throws -> XPAward {
        for log in session.exerciseLogs {
            for set in log.sets where set.repsCompleted == nil {
                set.repsCompleted = 0
            }
        }
        session.finishedAt = .now

        let settings = try context.fetch(FetchDescriptor<UserSettings>()).first
        settings?.lastCompletedWorkoutType = session.workoutType

        let unit = settings?.unit ?? .lb
        let newBadges = try BadgeCalculator.newlyUnlocked(for: session, unit: unit, in: context)
        let award = try awardXP(for: session, newBadges: newBadges, in: context)

        try context.save()
        return award
    }
```

Update `awardXP` to accept and forward `newBadges` (only the signature and the `XPAward(...)` construction change — the XP-math body is untouched):

```swift
    private static func awardXP(for session: WorkoutSession, newBadges: [Badge], in context: ModelContext) throws -> XPAward {
        let state: GamificationState
        if let existing = try context.fetch(FetchDescriptor<GamificationState>()).first {
            state = existing
        } else {
            state = GamificationState(totalXP: 0)
            context.insert(state)
        }

        let xpBefore = state.totalXP
        let base = XPCalculator.workoutXP
        let prCount = try newPRCount(for: session, in: context)
        let prBonus = prCount * XPCalculator.prBonusXP
        let isPerfect = !session.exerciseLogs.isEmpty && session.exerciseLogs.allSatisfy(\.succeeded)
        let perfectBonus = isPerfect ? XPCalculator.perfectBonusXP : 0
        let weeklyBonus = try isThirdFinishedWorkoutThisWeek(session, in: context) ? XPCalculator.weeklyBonusXP : 0
        let earned = base + prBonus + perfectBonus + weeklyBonus

        let award = XPAward(
            base: base,
            prCount: prCount,
            prBonus: prBonus,
            perfectBonus: perfectBonus,
            weeklyBonus: weeklyBonus,
            xpBefore: xpBefore,
            xpAfter: xpBefore + earned,
            newBadges: newBadges
        )
        state.totalXP = award.xpAfter
        return award
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd SwoleData && swift test`
Expected: PASS — the full `SwoleData` package suite, since this touches a widely-used type.

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/WorkoutSessionService.swift SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift
git commit -m "feat: report newly unlocked badges from finishWorkout"
```

---

### Task 6: `XPRevealView` — show newly unlocked badges

**Files:**
- Modify: `5x5ive/5x5ive/XPRevealView.swift`

**Interfaces:**
- Consumes: `award.newBadges: [Badge]` (Task 5), `Badge.iconName`, `Badge.title`.

- [ ] **Step 1: Add badge-reveal state and the badge list view**

In `XPRevealView`, add a new `@State` alongside the existing ones:

```swift
    @State private var visibleBadgeCount = 0
```

Add a computed property near `chips`:

```swift
    private var badges: [Badge] { award.newBadges }
```

Add the badge list view, placed in `body` right after `chipList` and before `levelBar`:

```swift
            if !badges.isEmpty {
                badgeList
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.top, 18)
            }
```

Add the `badgeList` view and its row alongside `chipList`:

```swift
    private var badgeList: some View {
        VStack(alignment: .leading, spacing: 9) {
            MetaLabel(text: "New Badges", color: Theme.textDim)
                .tracking(1.2)
            ForEach(Array(badges.enumerated()), id: \.offset) { index, badge in
                if index < visibleBadgeCount {
                    BadgeChipRow(badge: badge)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
```

Add the row type alongside `BonusChipRow` (bottom of the file):

```swift
private struct BadgeChipRow: View {
    let badge: Badge

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: badge.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentInk)
                .frame(width: 32, height: 32)
                .background(Theme.accent, in: Circle())
            Text(badge.title)
                .font(Theme.Font.body(15))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, Theme.Space.cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}
```

- [ ] **Step 2: Extend `animateIn()` to stagger the badge rows in after the XP chips**

Replace the existing `animateIn()` body's tail (from the `let barDelay = ...` line onward) with:

```swift
        let badgesStartDelay = 0.35 + Double(chips.count) * 0.18 + 0.15
        for index in badges.indices {
            let delay = badgesStartDelay + Double(index) * 0.18
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    visibleBadgeCount = index + 1
                }
            }
        }

        let barDelay = badgesStartDelay + Double(badges.count) * 0.18 + (badges.isEmpty ? 0 : 0.15)
        DispatchQueue.main.asyncAfter(deadline: .now() + barDelay) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                barFraction = endFraction
            }
        }
```

(This makes `badgesStartDelay` exactly equal to the old `barDelay`, so a workout with no new badges animates identically to today.)

- [ ] **Step 3: Build and manually verify**

Run: `cd 5x5ive && xcodebuild -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED. (An automated UI check of this screen's badge row is added in Task 8; this step is just confirming the view compiles and the reveal still renders normally for a no-badge workout, which Task 8's sibling test — the existing `testFinishingAWorkoutShowsTheXPRevealScreenWithTheEarnedTotal` — already exercises.)

- [ ] **Step 4: Commit**

```bash
git add 5x5ive/5x5ive/XPRevealView.swift
git commit -m "feat: reveal newly unlocked badges on the XP screen"
```

---

### Task 7: `StatsView` — Badges card

**Files:**
- Modify: `5x5ive/5x5ive/StatsView.swift`

**Interfaces:**
- Consumes: `BadgeCalculator.allBadges(unit:in:)` (Task 3), `Badge`, `BadgeCategory` (Task 2).

- [ ] **Step 1: Add badge state, loading, and the card to `StatsView`**

Add new `@State` alongside the existing ones:

```swift
    @State private var badges: [Badge] = []
    @State private var selectedBadge: Badge?
```

In `loadAll()`, add:

```swift
        badges = (try? BadgeCalculator.allBadges(unit: unit, in: modelContext)) ?? []
```

In `body`, add `badgesCard` after `recordsCard`, and attach the detail sheet to the outer `ScrollView`:

```swift
                recordsCard
                badgesCard
```

```swift
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailSheet(badge: badge, unit: unit)
                .presentationDetents([.height(260)])
        }
```

(Attach `.sheet` the same way `.task`/`.onChange` are already chained onto the `ScrollView` at the top of `body`.)

- [ ] **Step 2: Add the `badgesCard`, grouping, and tile grid**

Add near the other card properties (`recordsCard`, etc.):

```swift
    private var badgesCard: some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel(text: "Badges").tracking(1.6)
                Spacer()
                MetaLabel(text: "\(unlockedBadgeCount) / \(badges.count) earned", color: Theme.accentText)
            }

            ForEach(badgeGroups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 10) {
                    MetaLabel(text: group.title, color: Theme.textDim)
                    LazyVGrid(columns: badgeGridColumns, spacing: 12) {
                        ForEach(group.badges) { badge in
                            BadgeTile(badge: badge)
                                .onTapGesture { selectedBadge = badge }
                        }
                    }
                }
            }
        }
    }

    private var unlockedBadgeCount: Int { badges.filter(\.isUnlocked).count }

    private let badgeGridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    private struct BadgeGroup {
        let title: String
        let badges: [Badge]
    }

    private var badgeGroups: [BadgeGroup] {
        var groups: [BadgeGroup] = []

        let streakBadges = badges.filter { $0.category == .streak }
        if !streakBadges.isEmpty { groups.append(BadgeGroup(title: "Streaks", badges: streakBadges)) }

        let countBadges = badges.filter { $0.category == .workoutCount }
        if !countBadges.isEmpty { groups.append(BadgeGroup(title: "Workouts", badges: countBadges)) }

        let totalBadges = badges.filter { $0.category == .totalVolume }
        if !totalBadges.isEmpty { groups.append(BadgeGroup(title: "Total Volume", badges: totalBadges)) }

        for exercise in exercises {
            let exerciseBadges = badges.filter {
                guard case .exerciseVolume(let name) = $0.category else { return false }
                return name == exercise.name
            }
            if !exerciseBadges.isEmpty { groups.append(BadgeGroup(title: exercise.name, badges: exerciseBadges)) }
        }

        return groups
    }
```

- [ ] **Step 3: Add `BadgeTile` and `BadgeDetailSheet`**

Add these two new views at the bottom of `StatsView.swift`, alongside `VolumeBarChart`:

```swift
private struct BadgeTile: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(badge.isUnlocked ? Theme.accent : Theme.surfaceSunken)
                    .frame(width: 44, height: 44)
                Image(systemName: badge.isUnlocked ? badge.iconName : "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(badge.isUnlocked ? Theme.accentInk : Theme.textFaint)
            }
            Text(badge.progressTarget.formatted(.number.precision(.fractionLength(0))))
                .font(Theme.Font.numeric(11))
                .foregroundStyle(badge.isUnlocked ? Theme.textPrimary : Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BadgeDetailSheet: View {
    let badge: Badge
    let unit: MeasurementUnit

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: badge.iconName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(badge.isUnlocked ? Theme.accentText : Theme.textFaint)
                .frame(width: 72, height: 72)
                .background(badge.isUnlocked ? Theme.accent.opacity(0.15) : Theme.surfaceSunken, in: Circle())

            Text(badge.title)
                .font(Theme.Font.title(19))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            if badge.isUnlocked, let unlockedAt = badge.unlockedAt {
                MetaLabel(text: "Earned \(unlockedAt.formatted(date: .abbreviated, time: .omitted))", color: Theme.accentText)
            } else {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                .fill(Theme.surfaceSunken)
                            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                .fill(Theme.accent)
                                .frame(width: geo.size.width * progressFraction)
                        }
                    }
                    .frame(height: 8)
                    MetaLabel(text: "\(formattedProgress(badge.progressCurrent)) / \(formattedProgress(badge.progressTarget)) \(unitLabel)", color: Theme.textDim)
                }
            }
        }
        .padding(24)
    }

    private var progressFraction: CGFloat {
        guard badge.progressTarget > 0 else { return 0 }
        return min(CGFloat(badge.progressCurrent / badge.progressTarget), 1)
    }

    private var unitLabel: String {
        switch badge.category {
        case .exerciseVolume, .totalVolume: unit.rawValue
        case .workoutCount: "workouts"
        case .streak: "weeks"
        }
    }

    private func formattedProgress(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}
```

- [ ] **Step 4: Build and manually verify**

Run: `cd 5x5ive && xcodebuild -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED. Manually launch in the simulator, open Stats, confirm the Badges card renders with all locked tiles on a fresh install, and tapping one shows the detail sheet with a progress bar.

- [ ] **Step 5: Commit**

```bash
git add 5x5ive/5x5ive/StatsView.swift
git commit -m "feat: add the Badges card to Stats"
```

---

### Task 8: UI test for the badge reveal

**Files:**
- Modify: `5x5ive/5x5iveUITests/_x5iveUITests.swift`

**Interfaces:**
- Consumes: `launchApp()`, `setTile(in:labeled:value:)` — existing test helpers in this file.

- [ ] **Step 1: Write the test**

Add near `testFinishingAWorkoutShowsTheXPRevealScreenWithTheEarnedTotal` (same `// MARK: - Live Activity content state (regression)`-style section, or right after the existing XP reveal test):

```swift
    @MainActor
    func testFinishingAWorkoutThatCrossesAVolumeMilestoneShowsTheNewBadgesRow() throws {
        let app = launchApp()

        app.buttons["Start Workout A"].tap()
        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 5))

        // Log every set of Squat (45 lb x 5 reps x 5 sets = 1125 lb) so it
        // crosses the smallest 1,000 lb per-exercise volume tier. Skip the
        // rest timer between sets so the test doesn't wait it out.
        for setNumber in 1...5 {
            let set = app.descendants(matching: .any)["Set \(setNumber)"]
            XCTAssertTrue(set.waitForExistence(timeout: 5))
            set.tap()
            if setNumber < 5 {
                XCTAssertTrue(app.buttons["SKIP"].waitForExistence(timeout: 5))
                app.buttons["SKIP"].tap()
            }
        }

        app.buttons["Finish Workout"].tap()

        let alert = app.alerts["Some sets aren't logged"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Review & Finish"].tap()

        XCTAssertTrue(app.buttons["Complete Workout"].waitForExistence(timeout: 5))
        app.buttons["Complete Workout"].tap()

        XCTAssertTrue(app.staticTexts["NEW BADGES"].waitForExistence(timeout: 5))

        app.buttons["Done"].tap()
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd 5x5ive && xcodebuild test -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:5x5iveUITests/_x5iveUITests/testFinishingAWorkoutThatCrossesAVolumeMilestoneShowsTheNewBadgesRow`
Expected: FAIL — `NEW BADGES` text does not exist before Tasks 1–7 are implemented (run this before those tasks to confirm the test is meaningful, or immediately after them as a final end-to-end check — either way it must pass once Tasks 1–7 are in place).

- [ ] **Step 3: Run the full test target to verify everything passes together**

Run: `cd 5x5ive && xcodebuild test -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED, all tests pass (unit + UI), including the new badge-reveal test and the untouched `testFinishingAWorkoutShowsTheXPRevealScreenWithTheEarnedTotal`.

- [ ] **Step 4: Commit**

```bash
git add 5x5ive/5x5iveUITests/_x5iveUITests.swift
git commit -m "test: add UI coverage for the new-badges reveal"
```
