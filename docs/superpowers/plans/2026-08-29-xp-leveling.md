# XP + Leveling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Award XP for finishing a workout, bonus XP per new PR in a session, and a once-per-week bonus for hitting 3 finished workouts in a calendar week, with an indefinite level curve that flattens past level ~13.

**Architecture:** A new `GamificationState` SwiftData singleton model stores `totalXP`. A pure `XPCalculator` enum holds all XP/level constants and math (no persistence, fully unit-testable). `WorkoutSessionService.finishWorkout` — the single existing choke point where a session is marked finished — computes the award and adds it to `GamificationState.totalXP`. `TodayView` displays level + progress derived live from `totalXP` (never a stored level field).

**Tech Stack:** Swift 6.3, SwiftData, swift-testing (`@Test`/`#expect`, not XCTest), SwiftUI. Tests run via `swift test` from `SwoleData/` (no simulator needed — the package also targets macOS).

**Spec:** `docs/superpowers/specs/2026-08-29-xp-leveling-design.md`

## Global Constraints

- XP starts at 0 for everyone — no backfill of existing workout history.
- Level is always derived from `totalXP` via `XPCalculator`, never stored as its own field.
- PR bonus requires the exercise to have ≥1 prior *finished* session — the first-ever log of an exercise is a baseline, not a PR.
- The weekly bonus fires exactly once per calendar week, on the session that brings that week's finished-workout count to exactly 3.
- No UI history screen or award animations in this pass — just the level/XP bar on `TodayView`.

---

### Task 1: `GamificationState` model, schema, and seeding

**Files:**
- Create: `SwoleData/Sources/SwoleData/GamificationState.swift`
- Modify: `SwoleData/Sources/SwoleData/Schema.swift`
- Modify: `SwoleData/Sources/SwoleData/StandardSeed.swift:55` (insert alongside `UserSettings`)
- Test: `SwoleData/Tests/SwoleDataTests/GamificationStateTests.swift` (new)
- Test: `SwoleData/Tests/SwoleDataTests/StandardSeedTests.swift` (extend)

**Interfaces:**
- Produces: `GamificationState` (`@Model`, `public final class`, property `public var totalXP: Int`, `public init(totalXP: Int = 0)`), registered in `swoleSchema`. `StandardSeed.seed(in:)` now also inserts one `GamificationState(totalXP: 0)`.

- [ ] **Step 1: Write the failing model test**

Create `SwoleData/Tests/SwoleDataTests/GamificationStateTests.swift`:

```swift
import Testing
import SwiftData
@testable import SwoleData

@Test func gamificationStateStoresTotalXPAndDefaultsToZero() throws {
    let context = try makeInMemoryContext()

    let state = GamificationState()
    context.insert(state)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<GamificationState>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.totalXP == 0)

    fetched.first?.totalXP = 250
    try context.save()

    let refetched = try context.fetch(FetchDescriptor<GamificationState>())
    #expect(refetched.first?.totalXP == 250)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd SwoleData && swift test --filter gamificationStateStoresTotalXPAndDefaultsToZero`
Expected: FAIL to build — `GamificationState` is not defined, and it isn't in `swoleSchema` yet.

- [ ] **Step 3: Create the model and register it in the schema**

Create `SwoleData/Sources/SwoleData/GamificationState.swift`:

```swift
import SwiftData

@Model
public final class GamificationState {
    public var totalXP: Int

    public init(totalXP: Int = 0) {
        self.totalXP = totalXP
    }
}
```

Edit `SwoleData/Sources/SwoleData/Schema.swift` to add it to the schema:

```swift
import SwiftData

public let swoleSchema = Schema([
    Exercise.self,
    UserExerciseConfig.self,
    WorkoutTemplateExercise.self,
    WorkoutSession.self,
    ExerciseLog.self,
    SetLog.self,
    UserSettings.self,
    GamificationState.self,
])
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd SwoleData && swift test --filter gamificationStateStoresTotalXPAndDefaultsToZero`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/GamificationState.swift SwoleData/Sources/SwoleData/Schema.swift SwoleData/Tests/SwoleDataTests/GamificationStateTests.swift
git commit -m "feat: add GamificationState model"
```

- [ ] **Step 6: Write the failing seeding test**

Add this test to `SwoleData/Tests/SwoleDataTests/StandardSeedTests.swift` (append to the file):

```swift
@Test func seedCreatesGamificationStateStartingAtZeroXP() throws {
    let context = try makeInMemoryContext()

    _ = try StandardSeed.seed(in: context)

    let states = try context.fetch(FetchDescriptor<GamificationState>())
    #expect(states.count == 1)
    #expect(states.first?.totalXP == 0)
}
```

- [ ] **Step 7: Run the test to verify it fails**

Run: `cd SwoleData && swift test --filter seedCreatesGamificationStateStartingAtZeroXP`
Expected: FAIL — `states.count == 1` fails (0 states created).

- [ ] **Step 8: Seed it in StandardSeed**

Edit `SwoleData/Sources/SwoleData/StandardSeed.swift`, right after the existing `UserSettings` insert (currently line 55):

```swift
        context.insert(UserSettings(unit: .lb, lastCompletedWorkoutType: nil))
        context.insert(GamificationState(totalXP: 0))

        try context.save()
        return true
```

- [ ] **Step 9: Run the test to verify it passes**

Run: `cd SwoleData && swift test --filter seedCreatesGamificationStateStartingAtZeroXP`
Expected: PASS

- [ ] **Step 10: Run the full suite and commit**

Run: `cd SwoleData && swift test`
Expected: all tests pass (including the two new ones).

```bash
git add SwoleData/Sources/SwoleData/StandardSeed.swift SwoleData/Tests/SwoleDataTests/StandardSeedTests.swift
git commit -m "feat: seed GamificationState alongside UserSettings"
```

---

### Task 2: `XPCalculator` — XP constants and level curve math

**Files:**
- Create: `SwoleData/Sources/SwoleData/XPCalculator.swift`
- Test: `SwoleData/Tests/SwoleDataTests/XPCalculatorTests.swift` (new)

**Interfaces:**
- Consumes: nothing (pure, no dependency on Task 1).
- Produces: `XPCalculator.workoutXP: Int` (60), `XPCalculator.prBonusXP: Int` (20), `XPCalculator.weeklyBonusXP: Int` (120), `XPCalculator.xpForLevel(_ level: Int) -> Int`, `XPCalculator.level(forXP xp: Int) -> Int`, `XPCalculator.progress(forXP xp: Int) -> (current: Int, needed: Int, level: Int)`. Task 4 calls the XP constants; Task 5 (UI) calls `progress(forXP:)`.

- [ ] **Step 1: Write the failing tests**

Create `SwoleData/Tests/SwoleDataTests/XPCalculatorTests.swift`:

```swift
import Testing
@testable import SwoleData

@Test func xpConstantsMatchDesignedRates() {
    #expect(XPCalculator.workoutXP == 60)
    #expect(XPCalculator.prBonusXP == 20)
    #expect(XPCalculator.weeklyBonusXP == 120)
}

@Test func xpForLevelFollowsThePowerCurveBelowTheCap() {
    #expect(XPCalculator.xpForLevel(1) == 50)
    #expect(XPCalculator.xpForLevel(2) == 141)
    #expect(XPCalculator.xpForLevel(13) == 2344)
}

@Test func xpForLevelIsCappedAtTwentyFiveHundredPastLevelThirteen() {
    #expect(XPCalculator.xpForLevel(14) == 2500)
    #expect(XPCalculator.xpForLevel(20) == 2500)
    #expect(XPCalculator.xpForLevel(50) == 2500)
}

@Test func levelForXPStartsAtOneAndIncrementsAtEachThreshold() {
    #expect(XPCalculator.level(forXP: 0) == 1)
    #expect(XPCalculator.level(forXP: 49) == 1)
    #expect(XPCalculator.level(forXP: 50) == 2)
    #expect(XPCalculator.level(forXP: 190) == 2)
    #expect(XPCalculator.level(forXP: 191) == 3)
}

@Test func progressReportsXPEarnedWithinTheCurrentLevel() {
    let progress = XPCalculator.progress(forXP: 60)
    #expect(progress.level == 2)
    #expect(progress.current == 10)
    #expect(progress.needed == 141)
}

@Test func progressAtExactlyZeroXP() {
    let progress = XPCalculator.progress(forXP: 0)
    #expect(progress.level == 1)
    #expect(progress.current == 0)
    #expect(progress.needed == 50)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd SwoleData && swift test --filter XPCalculatorTests`
Expected: FAIL to build — `XPCalculator` is not defined.

- [ ] **Step 3: Implement XPCalculator**

Create `SwoleData/Sources/SwoleData/XPCalculator.swift`:

```swift
import Foundation

public enum XPCalculator {
    public static let workoutXP = 60
    public static let prBonusXP = 20
    public static let weeklyBonusXP = 120

    private static let levelCurveConstant = 50.0
    private static let levelCurveExponent = 1.5
    private static let levelCurveCap = 2500

    /// XP required to go from `level` to `level + 1`.
    public static func xpForLevel(_ level: Int) -> Int {
        let raw = levelCurveConstant * pow(Double(level), levelCurveExponent)
        return min(Int(raw.rounded()), levelCurveCap)
    }

    /// The level for a total XP amount. Level 1 starts at 0 XP.
    public static func level(forXP xp: Int) -> Int {
        progress(forXP: xp).level
    }

    /// XP earned within the current level, XP needed to complete it, and the current level.
    public static func progress(forXP xp: Int) -> (current: Int, needed: Int, level: Int) {
        var level = 1
        var remaining = xp
        while remaining >= xpForLevel(level) {
            remaining -= xpForLevel(level)
            level += 1
        }
        return (current: remaining, needed: xpForLevel(level), level: level)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd SwoleData && swift test --filter XPCalculatorTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/XPCalculator.swift SwoleData/Tests/SwoleDataTests/XPCalculatorTests.swift
git commit -m "feat: add XPCalculator with level curve"
```

---

### Task 3: `StatsCalculator.priorSucceededMaxWeight` — shared PR-detection helper

**Files:**
- Modify: `SwoleData/Sources/SwoleData/StatsCalculator.swift`
- Test: `SwoleData/Tests/SwoleDataTests/StatsCalculatorTests.swift` (extend)

**Interfaces:**
- Consumes: existing `ExerciseLog.succeeded`, `WorkoutSession`, the file's existing private `insertFinishedSession` test helper.
- Produces: `StatsCalculator.priorSucceededMaxWeight(for exercise: Exercise, before session: WorkoutSession, in context: ModelContext) throws -> Double?` — the highest `targetWeight` among *other* finished, succeeded sessions for that exercise, or `nil` if there are none. Task 4's `newPRCount` calls this directly.

- [ ] **Step 1: Write the failing tests**

Append to `SwoleData/Tests/SwoleDataTests/StatsCalculatorTests.swift` (after the `personalRecords` section, before `// MARK: - trendLogs`):

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd SwoleData && swift test --filter priorSucceededMaxWeight`
Expected: FAIL to build — `priorSucceededMaxWeight` is not defined on `StatsCalculator`.

- [ ] **Step 3: Implement the helper**

Edit `SwoleData/Sources/SwoleData/StatsCalculator.swift`, adding this method inside `enum StatsCalculator` (after `personalRecords`, before `trendLogs`):

```swift
    /// The highest `targetWeight` among other finished, successful sessions
    /// for this exercise — `nil` if there are none. Used to detect whether a
    /// session in progress of being finished just set a new PR.
    public static func priorSucceededMaxWeight(
        for exercise: Exercise,
        before session: WorkoutSession,
        in context: ModelContext
    ) throws -> Double? {
        let exerciseID = exercise.persistentModelID
        let sessionID = session.persistentModelID
        let logs = try context.fetch(FetchDescriptor<ExerciseLog>())
            .filter {
                $0.exercise?.persistentModelID == exerciseID
                    && $0.session?.persistentModelID != sessionID
                    && $0.session?.finishedAt != nil
                    && $0.succeeded
            }
        return logs.map(\.targetWeight).max()
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd SwoleData && swift test --filter priorSucceededMaxWeight`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/StatsCalculator.swift SwoleData/Tests/SwoleDataTests/StatsCalculatorTests.swift
git commit -m "feat: add StatsCalculator.priorSucceededMaxWeight for PR detection"
```

---

### Task 4: Award XP in `WorkoutSessionService.finishWorkout`

**Files:**
- Modify: `SwoleData/Sources/SwoleData/WorkoutSessionService.swift`
- Test: `SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift` (extend)

**Interfaces:**
- Consumes: `GamificationState` (Task 1), `XPCalculator.workoutXP/prBonusXP/weeklyBonusXP` (Task 2), `StatsCalculator.priorSucceededMaxWeight` (Task 3).
- Produces: `finishWorkout` now also mutates `GamificationState.totalXP`. No new public API — this is purely a behavior change inside the existing function, verified through `GamificationState` state after calling `finishWorkout`.

- [ ] **Step 1: Write the failing tests**

Append to `SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift`:

```swift
// MARK: - XP awards

@Test func finishWorkoutAwardsBaseXPOnlyWithNoPRsAndNotTheThirdWorkoutOfTheWeek() throws {
    let context = try makeSeededContext()
    let session = try WorkoutSessionService.startWorkout(in: context)

    try WorkoutSessionService.finishWorkout(session, in: context)

    let state = try context.fetch(FetchDescriptor<GamificationState>()).first
    #expect(state?.totalXP == XPCalculator.workoutXP)
}

@Test func finishWorkoutAwardsXPPerNewPRExerciseInTheSession() throws {
    let context = try makeSeededContext()

    let squat = try context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Squat" }!
    let bench = try context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Bench Press" }!

    // A prior finished session establishes a baseline for squat and bench.
    let priorStart = Date().addingTimeInterval(-7 * 24 * 3600)
    let priorSession = WorkoutSession(startedAt: priorStart, workoutType: .a, finishedAt: priorStart.addingTimeInterval(2400))
    context.insert(priorSession)
    let priorSquatLog = ExerciseLog(session: priorSession, exercise: squat, targetWeight: 135, targetReps: 5)
    context.insert(priorSquatLog)
    for n in 1...5 { context.insert(SetLog(exerciseLog: priorSquatLog, setNumber: n, repsCompleted: 5)) }
    let priorBenchLog = ExerciseLog(session: priorSession, exercise: bench, targetWeight: 95, targetReps: 5)
    context.insert(priorBenchLog)
    for n in 1...5 { context.insert(SetLog(exerciseLog: priorBenchLog, setNumber: n, repsCompleted: 5)) }

    let settings = try context.fetch(FetchDescriptor<UserSettings>()).first!
    settings.lastCompletedWorkoutType = .b
    try context.save()

    let session = try WorkoutSessionService.startWorkout(
        in: context,
        weightOverrides: [squat.persistentModelID: 185, bench.persistentModelID: 100]
    )
    for log in session.exerciseLogs where log.exercise?.name == "Squat" || log.exercise?.name == "Bench Press" {
        for set in log.sets { set.repsCompleted = log.targetReps }
    }

    try WorkoutSessionService.finishWorkout(session, in: context)

    let state = try context.fetch(FetchDescriptor<GamificationState>()).first
    #expect(state?.totalXP == XPCalculator.workoutXP + 2 * XPCalculator.prBonusXP)
}

@Test func finishWorkoutAwardsTheWeeklyBonusOnlyOnTheThirdFinishedWorkoutOfTheWeek() throws {
    let context = try makeSeededContext()
    let now = Date()
    let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: now)!.start

    for offset in [1, 2] {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStart)!
        let dummy = WorkoutSession(startedAt: date, workoutType: .a, finishedAt: date.addingTimeInterval(2400))
        context.insert(dummy)
    }
    try context.save()

    let settings = try context.fetch(FetchDescriptor<UserSettings>()).first!
    settings.lastCompletedWorkoutType = .b
    try context.save()

    let thirdSession = try WorkoutSessionService.startWorkout(in: context)
    try WorkoutSessionService.finishWorkout(thirdSession, in: context)

    let stateAfterThird = try context.fetch(FetchDescriptor<GamificationState>()).first
    #expect(stateAfterThird?.totalXP == XPCalculator.workoutXP + XPCalculator.weeklyBonusXP)

    let fourthSession = try WorkoutSessionService.startWorkout(in: context)
    try WorkoutSessionService.finishWorkout(fourthSession, in: context)

    let stateAfterFourth = try context.fetch(FetchDescriptor<GamificationState>()).first
    #expect(stateAfterFourth?.totalXP == (XPCalculator.workoutXP + XPCalculator.weeklyBonusXP) + XPCalculator.workoutXP)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd SwoleData && swift test --filter finishWorkoutAwards`
Expected: FAIL — `GamificationState.totalXP` stays 0 after `finishWorkout` (no award logic exists yet).

- [ ] **Step 3: Implement the award logic**

Edit `SwoleData/Sources/SwoleData/WorkoutSessionService.swift`. Replace `finishWorkout` and add two private helpers:

```swift
    public static func finishWorkout(_ session: WorkoutSession, in context: ModelContext) throws {
        for log in session.exerciseLogs {
            for set in log.sets where set.repsCompleted == nil {
                set.repsCompleted = 0
            }
        }
        session.finishedAt = .now

        let allSettings = try context.fetch(FetchDescriptor<UserSettings>())
        allSettings.first?.lastCompletedWorkoutType = session.workoutType

        try awardXP(for: session, in: context)

        try context.save()
    }

    private static func awardXP(for session: WorkoutSession, in context: ModelContext) throws {
        guard let state = try context.fetch(FetchDescriptor<GamificationState>()).first else { return }

        var xp = XPCalculator.workoutXP
        xp += try newPRCount(for: session, in: context) * XPCalculator.prBonusXP
        if try isThirdFinishedWorkoutThisWeek(session, in: context) {
            xp += XPCalculator.weeklyBonusXP
        }

        state.totalXP += xp
    }

    private static func newPRCount(for session: WorkoutSession, in context: ModelContext) throws -> Int {
        var count = 0
        for log in session.exerciseLogs {
            guard log.succeeded, let exercise = log.exercise else { continue }
            guard let priorBest = try StatsCalculator.priorSucceededMaxWeight(for: exercise, before: session, in: context) else { continue }
            if log.targetWeight > priorBest {
                count += 1
            }
        }
        return count
    }

    private static func isThirdFinishedWorkoutThisWeek(_ session: WorkoutSession, in context: ModelContext, calendar: Calendar = .current) throws -> Bool {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: session.startedAt) else { return false }
        let sessionID = session.persistentModelID
        let otherFinishedThisWeek = try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter {
                $0.persistentModelID != sessionID
                    && $0.finishedAt != nil
                    && weekInterval.contains($0.startedAt)
            }
        return otherFinishedThisWeek.count == 2
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd SwoleData && swift test --filter finishWorkoutAwards`
Expected: PASS

- [ ] **Step 5: Run the full suite and commit**

Run: `cd SwoleData && swift test`
Expected: all tests pass.

```bash
git add SwoleData/Sources/SwoleData/WorkoutSessionService.swift SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift
git commit -m "feat: award XP on workout finish"
```

---

### Task 5: Level/XP bar on `TodayView`

**Files:**
- Modify: `5x5ive/5x5ive/TodayView.swift`

**Interfaces:**
- Consumes: `GamificationState` (Task 1), `XPCalculator.progress(forXP:)` (Task 2).
- Produces: no new public API — a presentation-only view addition, verified manually.

- [ ] **Step 1: Add the query and progress computed property**

Edit `5x5ive/5x5ive/TodayView.swift`. Add a new `@Query` alongside the existing ones (after `finishedSessions`, around line 12):

```swift
    @Query private var gamificationStates: [GamificationState]
```

Add a computed property near `settings` (around line 17):

```swift
    private var xpProgress: (current: Int, needed: Int, level: Int) {
        XPCalculator.progress(forXP: gamificationStates.first?.totalXP ?? 0)
    }
```

- [ ] **Step 2: Add the XP bar view**

Add this private computed view, near `liftList` (after it, around line 88):

```swift
    private var xpBar: some View {
        let progress = xpProgress
        let fraction = progress.needed > 0 ? CGFloat(progress.current) / CGFloat(progress.needed) : 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                MetaLabel(text: "Level \(progress.level)", color: Theme.textDim)
                    .tracking(1.2)
                Spacer()
                MetaLabel(text: "\(progress.current) / \(progress.needed) XP", color: Theme.textDim)
                    .tracking(1.2)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.surfaceSunken)
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
    }
```

- [ ] **Step 3: Insert it into the body**

Edit the `body` in `5x5ive/5x5ive/TodayView.swift` (around line 34-40), inserting `xpBar` right after `WeekStrip`:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            WeekStrip(sessions: finishedSessions)
                .padding(.top, 22)
                .padding(.horizontal, Theme.Space.screen)

            xpBar
                .padding(.top, 14)
                .padding(.horizontal, Theme.Space.screen)

            liftList
                .padding(.top, 26)
                .padding(.horizontal, Theme.Space.screen)
```

(Only the two `xpBar` lines are new — the rest is unchanged, shown for placement.)

- [ ] **Step 4: Build the app target**

Run: `cd 5x5ive && xcodebuild -project 5x5ive.xcodeproj -scheme 5x5ive -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manual verification**

Launch the app in the simulator (via Xcode or `xcrun simctl`), finish a workout, and confirm:
- The level/XP bar appears under the week strip on `TodayView`.
- After finishing a workout, the XP bar's current/needed values increase by 60 (base) plus 20 per PR, and the progress fill grows accordingly.
- Finishing a 3rd workout within the same calendar week jumps the XP by an extra 120.

- [ ] **Step 6: Commit**

```bash
git add 5x5ive/5x5ive/TodayView.swift
git commit -m "feat: show level and XP progress on TodayView"
```

---

## Self-Review Notes

- **Spec coverage:** base XP (Task 4), PR bonus per exercise with baseline requirement (Tasks 3-4), weekly bonus fired once (Task 4), level curve with cap (Task 2), fresh-start/no-backfill (Task 1 — `totalXP` starts at 0, no migration of existing sessions), UI placement on `TodayView` (Task 5) — all covered.
- **Type consistency:** `GamificationState.totalXP: Int` used consistently across Tasks 1, 4, 5. `XPCalculator.progress(forXP:)` return tuple labels (`current`, `needed`, `level`) match between Task 2's implementation and Task 5's UI usage.
- **Out of scope confirmed:** no backfill migration, no history screen, no animations — none of the tasks above introduce them.
