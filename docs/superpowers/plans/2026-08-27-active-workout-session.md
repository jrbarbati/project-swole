# Active Workout Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full active-workout loop — start a workout (auto-computed from the template + progression logic), log every set with a tap-cycling button, get an advisory rest timer or exercise-transition prompt, finish (which permanently locks the session) or cancel (which deletes it), plus a minimal home screen and read-only history.

**Architecture:** `SwoleData` gets the schema changes (`WorkoutSession.finishedAt` as the lock flag, `ExerciseLog.order`, optional `SetLog.repsCompleted`, per-exercise rest durations), a `WorkoutSessionService` for the start/finish/cancel lifecycle, and an `ActiveWorkoutViewModel` that owns the tap-settle → rest-timer/interstitial state machine (kept UI-framework-free so it's directly unit testable). The `5x5ive` app target is pure SwiftUI views wired to these with `@Query`/`@Environment(\.modelContext)`; `ContentView` reactively shows `ActiveWorkoutView` whenever an unfinished session exists, so resuming mid-workout falls out for free.

**Tech Stack:** Swift 6.3, SwiftData, SwiftUI, Swift Testing (`@Test`/`#expect`), Observation (`@Observable`).

**Migration note:** The spec called for a `SchemaMigrationPlan`/`VersionedSchema`. This plan uses SwiftData's built-in *lightweight* migration instead — `@Attribute(originalName:)` for the `date` → `startedAt` rename, and stored property defaults (`= 0`, `= 90`, `= 180`) for new non-optional fields. SwiftData applies these automatically for a local store; no custom migration code is needed for this set of changes (rename, new optional field, new non-optional fields with defaults, widening `Int` → `Int?`). This is a deliberate simplification — the app has no shipped users yet — and is called out here rather than silently diverging from the spec.

---

## Task 1: `WorkoutSession` — rename `date` → `startedAt`, add `finishedAt`

**Files:**
- Modify: `SwoleData/Sources/SwoleData/WorkoutSession.swift`
- Modify: `SwoleData/Sources/SwoleData/ProgressionCalculator.swift:11`
- Modify: `SwoleData/Tests/SwoleDataTests/ExerciseLogTests.swift:14,40`
- Modify: `SwoleData/Tests/SwoleDataTests/ProgressionCalculatorTests.swift:36,63,95,126`

This is a mechanical rename plus one new optional field — no new behavior, so the existing test suite is the regression guard (no new test needed).

- [ ] **Step 1: Update the model**

Replace the contents of `SwoleData/Sources/SwoleData/WorkoutSession.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class WorkoutSession {
    @Attribute(originalName: "date")
    public var startedAt: Date
    public var workoutType: WorkoutType
    public var finishedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.session)
    public var exerciseLogs: [ExerciseLog] = []

    public init(startedAt: Date, workoutType: WorkoutType, finishedAt: Date? = nil) {
        self.startedAt = startedAt
        self.workoutType = workoutType
        self.finishedAt = finishedAt
    }
}
```

- [ ] **Step 2: Fix the one production call site**

In `SwoleData/Sources/SwoleData/ProgressionCalculator.swift`, line 11 currently reads:

```swift
            .sorted { ($0.session?.date ?? .distantPast) > ($1.session?.date ?? .distantPast) }
```

Change it to:

```swift
            .sorted { ($0.session?.startedAt ?? .distantPast) > ($1.session?.startedAt ?? .distantPast) }
```

- [ ] **Step 3: Fix test call sites**

In `SwoleData/Tests/SwoleDataTests/ExerciseLogTests.swift`, both occurrences of:

```swift
    let session = WorkoutSession(date: Date(), workoutType: .a)
```

become:

```swift
    let session = WorkoutSession(startedAt: Date(), workoutType: .a)
```

In `SwoleData/Tests/SwoleDataTests/ProgressionCalculatorTests.swift`, all four occurrences of `WorkoutSession(date:` become `WorkoutSession(startedAt:` (two use `Date()`, two use a local `date` variable — keep the argument expression as-is, only change the label):

```swift
    let session = WorkoutSession(startedAt: Date(), workoutType: .a)
```
```swift
    let session = WorkoutSession(startedAt: date, workoutType: .a)
```

- [ ] **Step 4: Run the full SwoleData test suite**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass, no compile errors.

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/WorkoutSession.swift SwoleData/Sources/SwoleData/ProgressionCalculator.swift SwoleData/Tests/SwoleDataTests/ExerciseLogTests.swift SwoleData/Tests/SwoleDataTests/ProgressionCalculatorTests.swift
git commit -m "Rename WorkoutSession.date to startedAt, add finishedAt as the session lock flag"
```

---

## Task 2: `SetLog.repsCompleted` becomes optional, `ExerciseLog` gets `order`

**Files:**
- Modify: `SwoleData/Sources/SwoleData/SetLog.swift`
- Modify: `SwoleData/Sources/SwoleData/ExerciseLog.swift`
- Test: `SwoleData/Tests/SwoleDataTests/ExerciseLogTests.swift`

`nil` = "not started" (distinct from `0` = "attempted, zero reps"). `ExerciseLog.order` snapshots template order so the carousel has a stable sequence (SwiftData to-many relationship arrays don't guarantee stored order).

- [ ] **Step 1: Write the failing test**

Add to `SwoleData/Tests/SwoleDataTests/ExerciseLogTests.swift`:

```swift
@Test func succeededIsFalseWhenAnySetIsNotStarted() throws {
    let context = try makeInMemoryContext()

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    let session = WorkoutSession(startedAt: Date(), workoutType: .a)
    context.insert(squat)
    context.insert(session)

    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 135, targetReps: 5)
    context.insert(log)
    for n in 1...4 {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: 5))
    }
    context.insert(SetLog(exerciseLog: log, setNumber: 5, repsCompleted: nil))
    try context.save()

    #expect(log.succeeded == false)
}
```

- [ ] **Step 2: Run test to verify it fails to compile**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter ExerciseLogTests`
Expected: FAIL — `nil is not compatible with expected argument type 'Int'` (repsCompleted is still non-optional).

- [ ] **Step 3: Update `SetLog`**

Replace the contents of `SwoleData/Sources/SwoleData/SetLog.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class SetLog {
    public var exerciseLog: ExerciseLog?
    public var setNumber: Int
    public var repsCompleted: Int?

    public init(exerciseLog: ExerciseLog?, setNumber: Int, repsCompleted: Int?) {
        self.exerciseLog = exerciseLog
        self.setNumber = setNumber
        self.repsCompleted = repsCompleted
    }
}
```

- [ ] **Step 4: Update `ExerciseLog`**

Replace the contents of `SwoleData/Sources/SwoleData/ExerciseLog.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class ExerciseLog {
    public var session: WorkoutSession?
    public var exercise: Exercise?
    public var targetWeight: Double
    public var targetReps: Int
    public var order: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \SetLog.exerciseLog)
    public var sets: [SetLog] = []

    public init(session: WorkoutSession?, exercise: Exercise?, targetWeight: Double, targetReps: Int, order: Int = 0) {
        self.session = session
        self.exercise = exercise
        self.targetWeight = targetWeight
        self.targetReps = targetReps
        self.order = order
    }

    public var succeeded: Bool {
        !sets.isEmpty && sets.allSatisfy { ($0.repsCompleted ?? Int.min) >= targetReps }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass, including the new `succeededIsFalseWhenAnySetIsNotStarted`.

- [ ] **Step 6: Commit**

```bash
git add SwoleData/Sources/SwoleData/SetLog.swift SwoleData/Sources/SwoleData/ExerciseLog.swift SwoleData/Tests/SwoleDataTests/ExerciseLogTests.swift
git commit -m "Make SetLog.repsCompleted optional (not-started vs zero) and add ExerciseLog.order"
```

---

## Task 3: Per-exercise rest timer durations on `UserExerciseConfig`

**Files:**
- Modify: `SwoleData/Sources/SwoleData/UserExerciseConfig.swift`
- Modify: `SwoleData/Sources/SwoleData/StandardSeed.swift`
- Test: `SwoleData/Tests/SwoleDataTests/StandardSeedTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `SwoleData/Tests/SwoleDataTests/StandardSeedTests.swift`:

```swift
@Test func seedSetsDefaultRestDurationsOnEveryConfig() throws {
    let context = try makeInMemoryContext()
    _ = try StandardSeed.seed(in: context)

    let configs = try context.fetch(FetchDescriptor<UserExerciseConfig>())
    #expect(configs.allSatisfy { $0.restSecondsOnSuccess == 90 })
    #expect(configs.allSatisfy { $0.restSecondsOnFail == 180 })
}
```

- [ ] **Step 2: Run test to verify it fails to compile**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter StandardSeedTests`
Expected: FAIL — `value of type 'UserExerciseConfig' has no member 'restSecondsOnSuccess'`.

- [ ] **Step 3: Update `UserExerciseConfig`**

Replace the contents of `SwoleData/Sources/SwoleData/UserExerciseConfig.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class UserExerciseConfig {
    public var exercise: Exercise?
    public var startingWeight: Double
    public var weightIncrement: Double
    public var setCount: Int
    public var repsPerSet: Int
    public var deloadThreshold: Int
    public var deloadPercentage: Double
    public var restSecondsOnSuccess: Int = 90
    public var restSecondsOnFail: Int = 180

    public init(
        exercise: Exercise?,
        startingWeight: Double,
        weightIncrement: Double,
        setCount: Int,
        repsPerSet: Int,
        deloadThreshold: Int,
        deloadPercentage: Double,
        restSecondsOnSuccess: Int = 90,
        restSecondsOnFail: Int = 180
    ) {
        self.exercise = exercise
        self.startingWeight = startingWeight
        self.weightIncrement = weightIncrement
        self.setCount = setCount
        self.repsPerSet = repsPerSet
        self.deloadThreshold = deloadThreshold
        self.deloadPercentage = deloadPercentage
        self.restSecondsOnSuccess = restSecondsOnSuccess
        self.restSecondsOnFail = restSecondsOnFail
    }
}
```

- [ ] **Step 4: Make `StandardSeed` set them explicitly**

In `SwoleData/Sources/SwoleData/StandardSeed.swift`, the `makeConfig` closure currently reads:

```swift
        func makeConfig(_ exercise: Exercise, starting: Double, increment: Double) {
            context.insert(UserExerciseConfig(
                exercise: exercise,
                startingWeight: starting,
                weightIncrement: increment,
                setCount: exercise.defaultSetCount,
                repsPerSet: exercise.defaultRepsPerSet,
                deloadThreshold: 3,
                deloadPercentage: 0.10
            ))
        }
```

Change it to:

```swift
        func makeConfig(_ exercise: Exercise, starting: Double, increment: Double) {
            context.insert(UserExerciseConfig(
                exercise: exercise,
                startingWeight: starting,
                weightIncrement: increment,
                setCount: exercise.defaultSetCount,
                repsPerSet: exercise.defaultRepsPerSet,
                deloadThreshold: 3,
                deloadPercentage: 0.10,
                restSecondsOnSuccess: 90,
                restSecondsOnFail: 180
            ))
        }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add SwoleData/Sources/SwoleData/UserExerciseConfig.swift SwoleData/Sources/SwoleData/StandardSeed.swift SwoleData/Tests/SwoleDataTests/StandardSeedTests.swift
git commit -m "Add per-exercise rest timer durations (90s success / 180s fail defaults)"
```

---

## Task 4: `RepCycle` — the tap-cycle pure function

**Files:**
- Create: `SwoleData/Sources/SwoleData/RepCycle.swift`
- Test: `SwoleData/Tests/SwoleDataTests/RepCycleTests.swift`

Cycle: `not started (nil) → target → target-1 → … → 1 → 0 → not started → target → …`

- [ ] **Step 1: Write the failing test**

Create `SwoleData/Tests/SwoleDataTests/RepCycleTests.swift`:

```swift
import Testing
@testable import SwoleData

@Test func cyclesFromNotStartedThroughTargetDownToZeroThenBackToNotStarted() {
    let target = 5
    var current: Int? = nil
    let expectedSequence: [Int?] = [5, 4, 3, 2, 1, 0, nil, 5]

    for expected in expectedSequence {
        current = RepCycle.next(current: current, target: target)
        #expect(current == expected)
    }
}

@Test func firstTapAlwaysLandsOnTargetRegardlessOfTargetValue() {
    #expect(RepCycle.next(current: nil, target: 5) == 5)
    #expect(RepCycle.next(current: nil, target: 1) == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter RepCycleTests`
Expected: FAIL — `cannot find 'RepCycle' in scope`.

- [ ] **Step 3: Implement `RepCycle`**

Create `SwoleData/Sources/SwoleData/RepCycle.swift`:

```swift
public enum RestOutcome: Equatable, Sendable {
    case success
    case fail
}

public enum RepCycle {
    public static func next(current: Int?, target: Int) -> Int? {
        guard let current else { return target }
        if current == 0 { return nil }
        return current - 1
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter RepCycleTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/RepCycle.swift SwoleData/Tests/SwoleDataTests/RepCycleTests.swift
git commit -m "Add RepCycle: pure tap-cycle sequence for logging a set's reps"
```

---

## Task 5: `ActiveWorkoutViewModel` — settle-based rest timer / transition prompt

**Files:**
- Create: `SwoleData/Sources/SwoleData/ActiveWorkoutViewModel.swift`
- Test: `SwoleData/Tests/SwoleDataTests/ActiveWorkoutViewModelTests.swift`

This is the resolved design for the rest timer: since the *first* tap out of "not started" always lands on `target` (by construction of `RepCycle`), firing the timer on that first tap would make `restSecondsOnFail` unreachable in normal use (landing on a below-target value takes several taps). Instead, each tap (re)starts a short **settle** countdown for that specific set; when taps on it stop for `settleDelay` (1.5s in the app, injectable for tests), the timer/interstitial fires using whatever value the set landed on. If it settles back on `nil` (reset to "not started"), nothing fires. The last set of an exercise shows a `TransitionPrompt` instead of a rest timer, using the same settle trigger.

This class is UI-framework-free (`Observation`, not `SwiftUI`) so it's directly unit testable without a view.

- [ ] **Step 1: Write the failing tests**

Create `SwoleData/Tests/SwoleDataTests/ActiveWorkoutViewModelTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter ActiveWorkoutViewModelTests`
Expected: FAIL — `cannot find 'ActiveWorkoutViewModel' in scope`.

- [ ] **Step 3: Implement `ActiveWorkoutViewModel`**

Create `SwoleData/Sources/SwoleData/ActiveWorkoutViewModel.swift`:

```swift
import Foundation
import SwiftData
import Observation

@Observable
public final class ActiveWorkoutViewModel {
    public struct ActiveRest: Equatable {
        public let outcome: RestOutcome
        public let endDate: Date
    }

    public struct TransitionPrompt: Equatable {
        public let exerciseName: String
        public let isFinalExercise: Bool
    }

    public private(set) var activeRest: ActiveRest?
    public private(set) var transitionPrompt: TransitionPrompt?

    private let settleDelay: Duration
    private var pendingSettleTasks: [PersistentIdentifier: Task<Void, Never>] = [:]

    public init(settleDelay: Duration = .milliseconds(1500)) {
        self.settleDelay = settleDelay
    }

    public func dismissTransitionPrompt() {
        transitionPrompt = nil
    }

    public func tap(set: SetLog, in log: ExerciseLog, isLastSet: Bool, isFinalExercise: Bool, config: UserExerciseConfig) {
        set.repsCompleted = RepCycle.next(current: set.repsCompleted, target: log.targetReps)

        let setID = set.persistentModelID
        pendingSettleTasks[setID]?.cancel()

        let capturedValue = set.repsCompleted
        let targetReps = log.targetReps
        let exerciseName = log.exercise?.name ?? ""
        let restSecondsOnSuccess = config.restSecondsOnSuccess
        let restSecondsOnFail = config.restSecondsOnFail
        let delay = settleDelay

        pendingSettleTasks[setID] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pendingSettleTasks[setID] = nil
            guard let value = capturedValue else { return }

            let outcome: RestOutcome = value >= targetReps ? .success : .fail
            if isLastSet {
                self?.transitionPrompt = TransitionPrompt(exerciseName: exerciseName, isFinalExercise: isFinalExercise)
            } else {
                let seconds = outcome == .success ? restSecondsOnSuccess : restSecondsOnFail
                self?.activeRest = ActiveRest(outcome: outcome, endDate: Date().addingTimeInterval(TimeInterval(seconds)))
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter ActiveWorkoutViewModelTests`
Expected: PASS (allow a few seconds — the tests use short real sleeps).

- [ ] **Step 5: Run the full suite**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add SwoleData/Sources/SwoleData/ActiveWorkoutViewModel.swift SwoleData/Tests/SwoleDataTests/ActiveWorkoutViewModelTests.swift
git commit -m "Add ActiveWorkoutViewModel: settle-based rest timer / exercise-transition prompt"
```

---

## Task 6: `WorkoutSessionService` — `activeSession` + `startWorkout`

**Files:**
- Create: `SwoleData/Sources/SwoleData/WorkoutSessionService.swift`
- Test: `SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter WorkoutSessionServiceTests`
Expected: FAIL — `cannot find 'WorkoutSessionService' in scope`.

- [ ] **Step 3: Implement**

Create `SwoleData/Sources/SwoleData/WorkoutSessionService.swift`:

```swift
import Foundation
import SwiftData

public enum WorkoutSessionServiceError: Error {
    case missingUserSettings
}

public enum WorkoutSessionService {
    public static func activeSession(in context: ModelContext) throws -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.finishedAt == nil }
        )
        descriptor.sortBy = [SortDescriptor(\.startedAt, order: .reverse)]
        return try context.fetch(descriptor).first
    }

    @discardableResult
    public static func startWorkout(in context: ModelContext) throws -> WorkoutSession {
        let settingsList = try context.fetch(FetchDescriptor<UserSettings>())
        guard let settings = settingsList.first else {
            throw WorkoutSessionServiceError.missingUserSettings
        }
        let workoutType = WorkoutScheduler.nextWorkoutType(after: settings)

        let allTemplateEntries = try context.fetch(FetchDescriptor<WorkoutTemplateExercise>())
        let entries = allTemplateEntries
            .filter { $0.workoutType == workoutType }
            .sorted { $0.order < $1.order }

        let configs = try context.fetch(FetchDescriptor<UserExerciseConfig>())

        let session = WorkoutSession(startedAt: .now, workoutType: workoutType)
        context.insert(session)

        for entry in entries {
            guard let exercise = entry.exercise else { continue }
            guard let config = configs.first(where: { $0.exercise?.persistentModelID == exercise.persistentModelID }) else {
                continue
            }

            let targetWeight = try ProgressionCalculator.nextTargetWeight(for: exercise, config: config, in: context)
            let log = ExerciseLog(
                session: session,
                exercise: exercise,
                targetWeight: targetWeight,
                targetReps: config.repsPerSet,
                order: entry.order
            )
            context.insert(log)

            for setNumber in 1...config.setCount {
                context.insert(SetLog(exerciseLog: log, setNumber: setNumber, repsCompleted: nil))
            }
        }

        try context.save()
        return session
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter WorkoutSessionServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/WorkoutSessionService.swift SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift
git commit -m "Add WorkoutSessionService.startWorkout: creates session/logs/sets from template + progression"
```

---

## Task 7: `WorkoutSessionService` — `finishWorkout` + `cancelWorkout`

**Files:**
- Modify: `SwoleData/Sources/SwoleData/WorkoutSessionService.swift`
- Modify: `SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter WorkoutSessionServiceTests`
Expected: FAIL — `type 'WorkoutSessionService' has no member 'finishWorkout'` (and `cancelWorkout`).

- [ ] **Step 3: Add the two functions**

In `SwoleData/Sources/SwoleData/WorkoutSessionService.swift`, add these two functions inside the `WorkoutSessionService` enum (after `startWorkout`):

```swift
    public static func finishWorkout(_ session: WorkoutSession, in context: ModelContext) throws {
        for log in session.exerciseLogs {
            for set in log.sets where set.repsCompleted == nil {
                set.repsCompleted = 0
            }
        }
        session.finishedAt = .now

        let settingsList = try context.fetch(FetchDescriptor<UserSettings>())
        settingsList.first?.lastCompletedWorkoutType = session.workoutType

        try context.save()
    }

    public static func cancelWorkout(_ session: WorkoutSession, in context: ModelContext) throws {
        context.delete(session)
        try context.save()
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/WorkoutSessionService.swift SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift
git commit -m "Add WorkoutSessionService.finishWorkout and cancelWorkout"
```

---

## Task 8: Seed on launch

**Files:**
- Modify: `5x5ive/5x5ive/_x5iveApp.swift`

Nothing seeds `Exercise`/`UserExerciseConfig`/`WorkoutTemplateExercise`/`UserSettings` today outside of tests — the app needs this data to exist before `HomeView` or `WorkoutSessionService.startWorkout` can do anything. Seed synchronously right after creating the container, before any view renders.

- [ ] **Step 1: Update `_x5iveApp.swift`**

Replace the contents of `5x5ive/5x5ive/_x5iveApp.swift`:

```swift
//
//  _x5iveApp.swift
//  5x5ive
//
//  Created by Joseph Barbati on 8/27/26.
//

import SwiftUI
import SwiftData
import SwoleData

@main
struct _x5iveApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = swoleSchema
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            let context = ModelContext(container)
            _ = try StandardSeed.seed(in: context)
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
```

- [ ] **Step 2: Build the app target**

Run: `cd /Users/josephbarbati/dev/project-swole/5x5ive && xcodebuild -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **` (existing `ContentView` is still the placeholder from before this plan, that's fine for this step).

- [ ] **Step 3: Commit**

```bash
git add 5x5ive/5x5ive/_x5iveApp.swift
git commit -m "Seed standard 5x5 setup synchronously on app launch"
```

---

## Task 9: Shared set-display components — `SetButtonView` + `ExerciseSetsView`

**Files:**
- Create: `5x5ive/5x5ive/SetButtonView.swift`
- Create: `5x5ive/5x5ive/ExerciseSetsView.swift`

These are shared by both the read-only history detail screen and the editable active-workout screen — `isEditable` toggles whether taps do anything.

- [ ] **Step 1: Create `SetButtonView.swift`**

```swift
import SwiftUI
import SwoleData

struct SetButtonView: View {
    let set: SetLog
    let isEditable: Bool
    let action: () -> Void

    private var label: String {
        guard let reps = set.repsCompleted else { return "—" }
        return "\(reps)"
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.title3.monospacedDigit())
                .frame(width: 48, height: 48)
                .background(set.repsCompleted == nil ? Color.gray.opacity(0.2) : Color.accentColor.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!isEditable)
    }
}

#Preview {
    SetButtonView(set: SetLog(exerciseLog: nil, setNumber: 1, repsCompleted: nil), isEditable: true, action: {})
}
```

- [ ] **Step 2: Create `ExerciseSetsView.swift`**

```swift
import SwiftUI
import SwoleData

struct ExerciseSetsView: View {
    let log: ExerciseLog
    let isEditable: Bool
    let onSetTap: ((SetLog) -> Void)?

    private var sortedSets: [SetLog] {
        log.sets.sorted { $0.setNumber < $1.setNumber }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(log.targetWeight.formatted()) lb × \(log.targetReps)")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(sortedSets) { set in
                    SetButtonView(set: set, isEditable: isEditable) {
                        onSetTap?(set)
                    }
                }
            }
        }
    }
}

#Preview {
    let log = ExerciseLog(session: nil, exercise: Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5), targetWeight: 135, targetReps: 5, order: 0)
    for n in 1...5 {
        log.sets.append(SetLog(exerciseLog: log, setNumber: n, repsCompleted: n <= 2 ? 5 : nil))
    }
    return ExerciseSetsView(log: log, isEditable: true, onSetTap: nil)
        .padding()
}
```

- [ ] **Step 3: Build the app target**

Run: `cd /Users/josephbarbati/dev/project-swole/5x5ive && xcodebuild -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`. (The new files sit under the file-system-synchronized `5x5ive/5x5ive` group, so Xcode picks them up automatically — no project file edits needed.)

- [ ] **Step 4: Commit**

```bash
git add 5x5ive/5x5ive/SetButtonView.swift 5x5ive/5x5ive/ExerciseSetsView.swift
git commit -m "Add shared SetButtonView and ExerciseSetsView components"
```

---

## Task 10: `HistoryListView` + `HistorySessionDetailView`

**Files:**
- Create: `5x5ive/5x5ive/HistoryListView.swift`
- Create: `5x5ive/5x5ive/HistorySessionDetailView.swift`

Read-only — no buttons, no tap-cycling, reachable only for sessions with `finishedAt != nil`.

- [ ] **Step 1: Create `HistorySessionDetailView.swift`**

```swift
import SwiftUI
import SwoleData

struct HistorySessionDetailView: View {
    let session: WorkoutSession

    private var sortedLogs: [ExerciseLog] {
        session.exerciseLogs.sorted { $0.order < $1.order }
    }

    var body: some View {
        List(sortedLogs) { log in
            Section(log.exercise?.name ?? "Unknown Exercise") {
                ExerciseSetsView(log: log, isEditable: false, onSetTap: nil)
            }
        }
        .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .omitted))
    }
}
```

- [ ] **Step 2: Create `HistoryListView.swift`**

```swift
import SwiftUI
import SwiftData
import SwoleData

struct HistoryListView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.finishedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var finishedSessions: [WorkoutSession]

    var body: some View {
        List(finishedSessions) { session in
            NavigationLink {
                HistorySessionDetailView(session: session)
            } label: {
                VStack(alignment: .leading) {
                    Text("Workout \(session.workoutType.rawValue) — \(session.startedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.headline)
                    Text(summary(for: session))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("History")
    }

    private func summary(for session: WorkoutSession) -> String {
        session.exerciseLogs
            .sorted { $0.order < $1.order }
            .map { log in "\(log.exercise?.name ?? "?") \(log.succeeded ? "✓" : "✗")" }
            .joined(separator: " · ")
    }
}
```

- [ ] **Step 3: Build the app target**

Run: `cd /Users/josephbarbati/dev/project-swole/5x5ive && xcodebuild -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add 5x5ive/5x5ive/HistoryListView.swift 5x5ive/5x5ive/HistorySessionDetailView.swift
git commit -m "Add read-only workout history list and detail views"
```

---

## Task 11: `RestTimerBanner` + `TransitionPromptView`

**Files:**
- Create: `5x5ive/5x5ive/RestTimerBanner.swift`
- Create: `5x5ive/5x5ive/TransitionPromptView.swift`

Both render `ActiveWorkoutViewModel` state; neither owns state of its own.

- [ ] **Step 1: Create `RestTimerBanner.swift`**

```swift
import SwiftUI
import SwoleData

struct RestTimerBanner: View {
    let rest: ActiveWorkoutViewModel.ActiveRest

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(rest.endDate.timeIntervalSince(context.date).rounded(.up)))
            if remaining > 0 {
                HStack {
                    Text(rest.outcome == .success ? "Rest" : "Rest — reset for next attempt")
                    Spacer()
                    Text("\(remaining)s")
                        .monospacedDigit()
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    RestTimerBanner(rest: .init(outcome: .success, endDate: .now.addingTimeInterval(90)))
}
```

- [ ] **Step 2: Create `TransitionPromptView.swift`**

```swift
import SwiftUI
import SwoleData

struct TransitionPromptView: View {
    let prompt: ActiveWorkoutViewModel.TransitionPrompt
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(prompt.isFinalExercise ? "Workout complete" : "Nice work on \(prompt.exerciseName)")
                .font(.title2.bold())
            Text(prompt.isFinalExercise ? "Tap Finish Workout when you're ready." : "Ready for the next exercise?")
                .foregroundStyle(.secondary)
            Button(prompt.isFinalExercise ? "OK" : "Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

#Preview {
    TransitionPromptView(prompt: .init(exerciseName: "Squat", isFinalExercise: false), onContinue: {})
}
```

- [ ] **Step 3: Build the app target**

Run: `cd /Users/josephbarbati/dev/project-swole/5x5ive && xcodebuild -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add 5x5ive/5x5ive/RestTimerBanner.swift 5x5ive/5x5ive/TransitionPromptView.swift
git commit -m "Add RestTimerBanner and TransitionPromptView"
```

---

## Task 12: `ActiveWorkoutView` — the carousel

**Files:**
- Create: `5x5ive/5x5ive/ActiveWorkoutView.swift`

Ties `ActiveWorkoutViewModel`, `ExerciseSetsView`, `RestTimerBanner`, and `TransitionPromptView` together. Finish Workout confirms only if any set is still unset (per the design spec); Cancel Workout always confirms (destructive).

- [ ] **Step 1: Create `ActiveWorkoutView.swift`**

```swift
import SwiftUI
import SwiftData
import SwoleData

struct ActiveWorkoutView: View {
    let session: WorkoutSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var configs: [UserExerciseConfig]
    @State private var viewModel = ActiveWorkoutViewModel()
    @State private var currentIndex = 0
    @State private var showFinishConfirmation = false
    @State private var showCancelConfirmation = false

    private var sortedLogs: [ExerciseLog] {
        session.exerciseLogs.sorted { $0.order < $1.order }
    }

    private var hasUnloggedSets: Bool {
        sortedLogs.contains { log in log.sets.contains { $0.repsCompleted == nil } }
    }

    var body: some View {
        VStack {
            if sortedLogs.isEmpty {
                Text("No exercises in this workout.")
            } else {
                let log = sortedLogs[currentIndex]
                let config = configs.first { $0.exercise?.persistentModelID == log.exercise?.persistentModelID }

                HStack {
                    Button("←") { currentIndex -= 1 }
                        .disabled(currentIndex == 0)
                    Spacer()
                    Text("\(log.exercise?.name ?? "") \(currentIndex + 1)/\(sortedLogs.count)")
                        .font(.headline)
                    Spacer()
                    Button("→") { currentIndex += 1 }
                        .disabled(currentIndex == sortedLogs.count - 1)
                }
                .padding(.horizontal)

                if let config {
                    ExerciseSetsView(log: log, isEditable: true) { set in
                        let sortedSets = log.sets.sorted { $0.setNumber < $1.setNumber }
                        let isLastSet = set.setNumber == sortedSets.last?.setNumber
                        viewModel.tap(
                            set: set,
                            in: log,
                            isLastSet: isLastSet,
                            isFinalExercise: currentIndex == sortedLogs.count - 1,
                            config: config
                        )
                    }
                } else {
                    Text("Missing configuration for \(log.exercise?.name ?? "this exercise").")
                }

                Spacer()

                if let activeRest = viewModel.activeRest {
                    RestTimerBanner(rest: activeRest)
                }
            }
        }
        .padding(.top)
        .overlay {
            if let prompt = viewModel.transitionPrompt {
                TransitionPromptView(prompt: prompt) {
                    viewModel.dismissTransitionPrompt()
                    if !prompt.isFinalExercise, currentIndex < sortedLogs.count - 1 {
                        currentIndex += 1
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel Workout", role: .destructive) {
                    showCancelConfirmation = true
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Finish Workout") {
                    if hasUnloggedSets {
                        showFinishConfirmation = true
                    } else {
                        finish()
                    }
                }
            }
        }
        .alert("Some sets aren't logged", isPresented: $showFinishConfirmation) {
            Button("Finish Anyway", role: .destructive) { finish() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Any unlogged sets will be recorded as 0 reps. This can't be undone.")
        }
        .alert("Cancel this workout?", isPresented: $showCancelConfirmation) {
            Button("Delete Workout", role: .destructive) { cancel() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("This deletes everything logged in this session. This can't be undone.")
        }
    }

    private func finish() {
        try? WorkoutSessionService.finishWorkout(session, in: modelContext)
        dismiss()
    }

    private func cancel() {
        try? WorkoutSessionService.cancelWorkout(session, in: modelContext)
        dismiss()
    }
}
```

Note: `currentIndex` starts at `0` here (first exercise), not "first exercise with an unstarted set" — that resume-index refinement is picked up in Task 13 once `ContentView` is wired up and can pass an initial index in.

- [ ] **Step 2: Build the app target**

Run: `cd /Users/josephbarbati/dev/project-swole/5x5ive && xcodebuild -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add 5x5ive/5x5ive/ActiveWorkoutView.swift
git commit -m "Add ActiveWorkoutView: the one-exercise-at-a-time carousel"
```

---

## Task 13: `HomeView` + `ContentView` routing (resume-on-launch)

**Files:**
- Create: `5x5ive/5x5ive/HomeView.swift`
- Modify: `5x5ive/5x5ive/ContentView.swift`
- Modify: `5x5ive/5x5ive/ActiveWorkoutView.swift`

`ContentView` reactively shows `ActiveWorkoutView` whenever `@Query` finds an unfinished session — this is what makes mid-workout relaunch "just resume," with no explicit resume logic needed. `HomeView`'s Start Workout button doesn't navigate anywhere itself; creating the session is enough for `ContentView` to switch over on its own.

- [ ] **Step 1: Create `HomeView.swift`**

```swift
import SwiftUI
import SwiftData
import SwoleData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [UserSettings]
    @Query(sort: \WorkoutTemplateExercise.order) private var templateEntries: [WorkoutTemplateExercise]
    @State private var startError: String?

    private var settings: UserSettings? { settingsList.first }

    private var nextWorkoutType: WorkoutType {
        guard let settings else { return .a }
        return WorkoutScheduler.nextWorkoutType(after: settings)
    }

    private var nextExercises: [WorkoutTemplateExercise] {
        templateEntries.filter { $0.workoutType == nextWorkoutType }
    }

    var body: some View {
        List {
            Section("Next Workout") {
                Text("Workout \(nextWorkoutType.rawValue)")
                    .font(.title2.bold())
                ForEach(nextExercises) { entry in
                    Text(entry.exercise?.name ?? "Unknown Exercise")
                }
                Button("Start Workout") {
                    startWorkout()
                }
                .disabled(settings == nil)
            }

            Section {
                NavigationLink("History") {
                    HistoryListView()
                }
            }

            if let startError {
                Text(startError)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("5x5ive")
    }

    private func startWorkout() {
        do {
            _ = try WorkoutSessionService.startWorkout(in: modelContext)
        } catch {
            startError = "Couldn't start workout: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 2: Give `ActiveWorkoutView` an initial-index parameter**

In `5x5ive/5x5ive/ActiveWorkoutView.swift`, change:

```swift
    @State private var currentIndex = 0
```

to:

```swift
    @State private var currentIndex: Int

    init(session: WorkoutSession) {
        self.session = session
        let logs = session.exerciseLogs.sorted { $0.order < $1.order }
        let firstIncomplete = logs.firstIndex { log in log.sets.contains { $0.repsCompleted == nil } }
        _currentIndex = State(initialValue: firstIncomplete ?? max(0, logs.count - 1))
    }
```

Also remove the now-redundant `let session: WorkoutSession` stored property declaration at the top of the struct (it's set in `init` now) — the file should read:

```swift
struct ActiveWorkoutView: View {
    let session: WorkoutSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var configs: [UserExerciseConfig]
    @State private var viewModel = ActiveWorkoutViewModel()
    @State private var currentIndex: Int
    @State private var showFinishConfirmation = false
    @State private var showCancelConfirmation = false

    init(session: WorkoutSession) {
        self.session = session
        let logs = session.exerciseLogs.sorted { $0.order < $1.order }
        let firstIncomplete = logs.firstIndex { log in log.sets.contains { $0.repsCompleted == nil } }
        _currentIndex = State(initialValue: firstIncomplete ?? max(0, logs.count - 1))
    }

    private var sortedLogs: [ExerciseLog] {
```

(everything from `private var sortedLogs` onward is unchanged from Task 12).

- [ ] **Step 3: Update `ContentView.swift`**

Replace the contents of `5x5ive/5x5ive/ContentView.swift`:

```swift
//
//  ContentView.swift
//  5x5ive
//
//  Created by Joseph Barbati on 8/27/26.
//

import SwiftUI
import SwiftData
import SwoleData

struct ContentView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.finishedAt == nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var activeSessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            if let activeSession = activeSessions.first {
                ActiveWorkoutView(session: activeSession)
            } else {
                HomeView()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: swoleSchema, inMemory: true)
}
```

- [ ] **Step 4: Build the app target**

Run: `cd /Users/josephbarbati/dev/project-swole/5x5ive && xcodebuild -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add 5x5ive/5x5ive/HomeView.swift 5x5ive/5x5ive/ContentView.swift 5x5ive/5x5ive/ActiveWorkoutView.swift
git commit -m "Add HomeView and wire ContentView to auto-resume an in-progress session"
```

---

## Task 14: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full SwoleData test suite**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass (this now includes the original `ProgressionCalculator`/`WorkoutScheduler` tests plus everything added in Tasks 1–7).

- [ ] **Step 2: Build the app target one more time, clean**

Run: `cd /Users/josephbarbati/dev/project-swole/5x5ive && xcodebuild -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' clean build 2>&1 | tail -40`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual walkthrough in the Simulator**

Boot the simulator and install/launch the app, then click through the golden path by hand (this is UI behavior — tap timing, live countdowns, and confirmation dialogs — that isn't covered by the automated tests above):

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null || true
open -a Simulator
cd /Users/josephbarbati/dev/project-swole/5x5ive
xcodebuild -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build install 2>&1 | tail -20
xcrun simctl install "iPhone 17" build/Build/Products/Debug-iphonesimulator/5x5ive.app
xcrun simctl launch "iPhone 17" $(defaults read "$(pwd)/build/Build/Products/Debug-iphonesimulator/5x5ive.app/Info" CFBundleIdentifier)
```

Verify, in order:
1. Home screen shows "Workout A" with Squat/Bench Press/Barbell Row listed.
2. Tap Start Workout → carousel opens on Squat, showing 5 "—" buttons and "45 lb × 5".
3. Tap the first set button 5 times: it cycles 5 → 4 → 3 → 2 → 1 → 0 → back to "—", confirming the reset behavior.
4. Tap it once (lands on 5) and wait ~2 seconds without tapping again — a "Rest / 90s" banner appears and counts down.
5. Tap another set 3 times to land on 3 (a fail value) and wait — the banner should read the fail duration (180s) once it appears, not 90s.
6. Log all 5 Squat sets, then log the 5th (last) set — instead of a rest banner, a "Nice work on Squat — ready for Bench Press?" prompt appears; tapping Continue advances to Bench Press.
7. Finish Bench Press and Barbell Row's last sets similarly; on Barbell Row (the last exercise) the final prompt should read "Workout complete."
8. Tap Finish Workout. If any set is still unlogged, confirm the "Some sets aren't logged" alert appears and finishing sets it to 0; otherwise it finishes immediately.
9. Confirm you land back on the Home screen, and Home now shows "Workout B" as next.
10. Open History → the just-finished session appears with a pass/fail summary; opening it shows the same weights/reps read-only, with no tappable set buttons.
11. Start a new workout, tap a couple of sets, then tap Cancel Workout → confirm the deletion alert → confirm you're back on Home showing the *same* next workout type as before (not advanced), and History does not contain the cancelled session.
12. Force-quit and relaunch the app mid-workout (after Start Workout, before Finish) → confirm it reopens directly into the active carousel rather than Home.

If anything in this walkthrough doesn't match, fix it before considering this plan complete — this is the actual feature working end to end, not just compiling.

- [ ] **Step 4: Report results to the user**

Summarize what was verified and flag anything from Step 3 that didn't behave as expected.
