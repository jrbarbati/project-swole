# TodayView Inline Weight Adjust + Live Delta Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user nudge a lift's planned weight for today's workout with `−`/`+` buttons in TodayView, with the delta label below it updating live, without touching persisted state until the workout actually starts.

**Architecture:** TodayView holds a local `[PersistentIdentifier: Double]` dictionary of pending weight adjustments, keyed by exercise. `NextLiftRow` becomes purely presentational (resolved weight + delta in, tap callbacks out). A new `ProgressionCalculator.lastCompletedWeight` helper supplies the baseline the delta is measured against. `WorkoutSessionService.startWorkout` gains an optional `weightOverrides` param so the adjustment is baked into the new session's `ExerciseLog` without ever writing to `UserExerciseConfig`.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing (`@Test`/`#expect`) for the `SwoleData` package, XCUITest for the app.

Spec: `docs/superpowers/specs/2026-08-28-today-view-weight-adjust-design.md`

---

### Task 1: `ProgressionCalculator.lastCompletedWeight` helper

**Files:**
- Modify: `SwoleData/Sources/SwoleData/ProgressionCalculator+Redesign.swift`
- Test: `SwoleData/Tests/SwoleDataTests/ProgressionCalculatorRedesignTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to the end of `SwoleData/Tests/SwoleDataTests/ProgressionCalculatorRedesignTests.swift`:

```swift
@Test func lastCompletedWeightIsNilWithNoFinishedHistory() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    try context.save()

    let weight = try ProgressionCalculator.lastCompletedWeight(for: squat, in: context)
    #expect(weight == nil)
}

@Test func lastCompletedWeightReturnsTheMostRecentFinishedLogsWeight() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let calendar = Calendar.current
    let day0 = Date()
    let day1 = calendar.date(byAdding: .day, value: 1, to: day0)!

    _ = makeFinishedSession(for: squat, on: day0, targetWeight: 135, in: context)
    _ = makeFinishedSession(for: squat, on: day1, targetWeight: 140, in: context)
    try context.save()

    let weight = try ProgressionCalculator.lastCompletedWeight(for: squat, in: context)
    #expect(weight == 140)
}

@Test func lastCompletedWeightIgnoresInProgressSessions() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    _ = makeFinishedSession(for: squat, on: Date(), targetWeight: 135, in: context)

    let inProgress = WorkoutSession(startedAt: Date(), workoutType: .a)
    context.insert(inProgress)
    context.insert(ExerciseLog(session: inProgress, exercise: squat, targetWeight: 999, targetReps: 5))
    try context.save()

    let weight = try ProgressionCalculator.lastCompletedWeight(for: squat, in: context)
    #expect(weight == 135)
}
```

These reuse the existing `makeFinishedSession` helper already defined at the top of this test file.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SwoleData && swift test --filter ProgressionCalculatorRedesignTests`
Expected: FAIL — `lastCompletedWeight` is not a member of `ProgressionCalculator` (compile error).

- [ ] **Step 3: Implement the helper**

In `SwoleData/Sources/SwoleData/ProgressionCalculator+Redesign.swift`, add inside the existing `public extension ProgressionCalculator { ... }` block, after `previousLog`:

```swift
    /// The `targetWeight` of the most recent *finished* session for this
    /// exercise, or `nil` if it's never been logged. Used as the baseline
    /// a live weight-adjustment delta is measured against.
    static func lastCompletedWeight(for exercise: Exercise, in context: ModelContext) throws -> Double? {
        try recentLogs(for: exercise, limit: 1, in: context).last?.targetWeight
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SwoleData && swift test --filter ProgressionCalculatorRedesignTests`
Expected: PASS (all tests in the file, including the 3 new ones).

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/ProgressionCalculator+Redesign.swift SwoleData/Tests/SwoleDataTests/ProgressionCalculatorRedesignTests.swift
git commit -m "Add ProgressionCalculator.lastCompletedWeight helper"
```

---

### Task 2: `WorkoutSessionService.startWorkout` honors a per-exercise weight override map

**Files:**
- Modify: `SwoleData/Sources/SwoleData/WorkoutSessionService.swift`
- Test: `SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift`

- [ ] **Step 1: Write the failing test**

Add to the end of `SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift`:

```swift
@Test func startWorkoutPrefersAnExplicitWeightOverrideOverConfigAndComputedWeight() throws {
    let context = try makeSeededContext()

    let squat = try context.fetch(FetchDescriptor<Exercise>())
        .first { $0.name == "Squat" }
    let config = try context.fetch(FetchDescriptor<UserExerciseConfig>())
        .first { $0.exercise?.persistentModelID == squat?.persistentModelID }
    config?.weightOverride = 225
    try context.save()

    let session = try WorkoutSessionService.startWorkout(
        in: context,
        weightOverrides: [squat!.persistentModelID: 250]
    )

    let squatLog = session.exerciseLogs.first { $0.exercise?.name == "Squat" }
    #expect(squatLog?.targetWeight == 250)
    #expect(config?.weightOverride == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SwoleData && swift test --filter WorkoutSessionServiceTests`
Expected: FAIL — extra argument `weightOverrides` in call to `startWorkout` (compile error).

- [ ] **Step 3: Implement the param**

In `SwoleData/Sources/SwoleData/WorkoutSessionService.swift`, change `startWorkout` and `insertExerciseLog`:

```swift
    @discardableResult
    public static func startWorkout(
        in context: ModelContext,
        weightOverrides: [PersistentIdentifier: Double] = [:]
    ) throws -> WorkoutSession {
        guard let settings = try context.fetch(FetchDescriptor<UserSettings>()).first else {
            throw WorkoutSessionServiceError.missingUserSettings
        }
        let workoutType = WorkoutScheduler.nextWorkoutType(after: settings)

        let allTemplateEntries = try context.fetch(FetchDescriptor<WorkoutTemplateExercise>())
        let entriesForWorkout = allTemplateEntries
            .filter { $0.workoutType == workoutType }
            .sorted { $0.order < $1.order }

        let configs = try context.fetch(FetchDescriptor<UserExerciseConfig>())

        let session = WorkoutSession(startedAt: .now, workoutType: workoutType)
        context.insert(session)

        for entry in entriesForWorkout {
            guard let exercise = entry.exercise,
                  let config = configs.first(where: { $0.exercise?.persistentModelID == exercise.persistentModelID })
            else { continue }

            try insertExerciseLog(
                for: exercise,
                config: config,
                order: entry.order,
                in: session,
                weightOverride: weightOverrides[exercise.persistentModelID],
                context: context
            )
        }

        try context.save()
        return session
    }

    private static func insertExerciseLog(
        for exercise: Exercise,
        config: UserExerciseConfig,
        order: Int,
        in session: WorkoutSession,
        weightOverride: Double?,
        context: ModelContext
    ) throws {
        let targetWeight = try weightOverride
            ?? ProgressionCalculator.nextTargetWeight(for: exercise, config: config, in: context)
        config.weightOverride = nil
        let log = ExerciseLog(
            session: session,
            exercise: exercise,
            targetWeight: targetWeight,
            targetReps: config.repsPerSet,
            order: order
        )
        context.insert(log)

        for setNumber in 1...config.setCount {
            context.insert(SetLog(exerciseLog: log, setNumber: setNumber, repsCompleted: nil))
        }
    }
```

Note `let targetWeight = try weightOverride ?? ProgressionCalculator.nextTargetWeight(...)` — `??` short-circuits, so `nextTargetWeight` (and its `try`) only runs when there's no override.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SwoleData && swift test`
Expected: PASS — full suite, including the existing `startWorkoutConsumesWeightOverrideIntoTheLogAndClearsIt` test (confirms the default `weightOverrides: [:]` keeps old behavior) and the new one.

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/WorkoutSessionService.swift SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift
git commit -m "Let startWorkout take an explicit per-exercise weight override map"
```

---

### Task 3: TodayView UI test for the adjust/discard flow (written first, expected to fail)

**Files:**
- Modify: `5x5ive/5x5iveUITests/_x5iveUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Add to `_x5iveUITests` (inside the class, after `testCancelingWorkoutReturnsToTodayTab`):

```swift
    // MARK: - Today view weight adjust

    @MainActor
    func testAdjustingWeightUpdatesDisplayAndDeltaLiveWithoutPersisting() throws {
        let app = launchApp()

        // Squat's un-adjusted plan: starting weight 45, no history yet, so delta reads HOLD.
        XCTAssertTrue(app.staticTexts["45"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HOLD"].waitForExistence(timeout: 5))

        app.buttons["weightIncrement-Squat"].tap()

        XCTAssertTrue(app.staticTexts["50"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["+5"].waitForExistence(timeout: 5))

        // Swapping the planned workout discards the pending adjustment.
        app.buttons["swapWorkoutButton"].tap()
        app.buttons["swapWorkoutButton"].tap()

        XCTAssertTrue(app.staticTexts["45"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HOLD"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStartingWorkoutBakesInTheAdjustedWeight() throws {
        let app = launchApp()

        app.buttons["weightIncrement-Squat"].tap()
        XCTAssertTrue(app.staticTexts["50"].waitForExistence(timeout: 5))

        app.buttons["Start Workout A"].tap()

        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["50"].waitForExistence(timeout: 5))
    }
```

`swapWorkoutButton` is tapped twice: the scheduler alternates A/B off `lastCompletedWorkoutType`, so one swap moves to B and a second swap moves back to A — the test only checks that Squat's row (Workout A's first lift) returns to its unadjusted state, which requires being back on A.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd 5x5ive && xcodebuild test -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:5x5iveUITests/_x5iveUITests/testAdjustingWeightUpdatesDisplayAndDeltaLiveWithoutPersisting -only-testing:5x5iveUITests/_x5iveUITests/testStartingWorkoutBakesInTheAdjustedWeight`
Expected: FAIL — `app.buttons["weightIncrement-Squat"]` and `app.buttons["swapWorkoutButton"]` don't exist yet (no matching element / timeout), and `"HOLD"` won't be found under Squat since today's delta label is still failStreak-based.

- [ ] **Step 3: Commit the failing test**

```bash
git add 5x5ive/5x5iveUITests/_x5iveUITests.swift
git commit -m "Add failing UI tests for TodayView weight adjust"
```

---

### Task 4: TodayView implementation

**Files:**
- Modify: `5x5ive/5x5ive/TodayView.swift`

- [ ] **Step 1: Add adjustment state and resolution helpers**

In `TodayView`, add the state property near `startError` and the helper functions near `targetWeight(for:config:)`:

```swift
    @State private var startError: String?
    @State private var weightAdjustments: [PersistentIdentifier: Double] = [:]
```

```swift
    private func targetWeight(for exercise: Exercise, config: UserExerciseConfig) -> Double {
        (try? ProgressionCalculator.nextTargetWeight(for: exercise, config: config, in: modelContext))
            ?? config.startingWeight
    }

    /// The weight to show for this exercise: a pending local adjustment if
    /// the user has tapped −/+, otherwise the calculated plan.
    private func displayWeight(for exercise: Exercise, config: UserExerciseConfig) -> Double {
        weightAdjustments[exercise.persistentModelID] ?? targetWeight(for: exercise, config: config)
    }

    /// What the delta below the weight is measured against: the last
    /// actually-completed weight for this lift, or its starting weight if
    /// it's never been logged.
    private func baselineWeight(for exercise: Exercise, config: UserExerciseConfig) -> Double {
        (try? ProgressionCalculator.lastCompletedWeight(for: exercise, in: modelContext))
            ?? config.startingWeight
    }

    private func adjustWeight(for exercise: Exercise, config: UserExerciseConfig, by delta: Double) {
        let current = displayWeight(for: exercise, config: config)
        weightAdjustments[exercise.persistentModelID] = max(0, current + delta)
    }
```

- [ ] **Step 2: Wire `liftList` to pass resolved weight, delta, and tap callbacks**

Replace the `liftList` body:

```swift
    private var liftList: some View {
        VStack(spacing: Theme.Space.cardGap) {
            ForEach(nextEntries) { entry in
                if let exercise = entry.exercise, let config = config(for: exercise) {
                    NextLiftRow(
                        exercise: exercise,
                        config: config,
                        unit: settings?.unit ?? .lb,
                        targetWeight: displayWeight(for: exercise, config: config),
                        delta: displayWeight(for: exercise, config: config) - baselineWeight(for: exercise, config: config),
                        onDecrement: { adjustWeight(for: exercise, config: config, by: -config.weightIncrement) },
                        onIncrement: { adjustWeight(for: exercise, config: config, by: config.weightIncrement) }
                    )
                }
            }
            if let holdNote {
                MetaLabel(text: holdNote, color: Theme.textFaint)
                    .padding(.horizontal, 4)
            }
        }
    }
```

- [ ] **Step 3: Update `startWorkout()` and `swapWorkout()`**

```swift
    private func startWorkout() {
        do {
            _ = try WorkoutSessionService.startWorkout(in: modelContext, weightOverrides: weightAdjustments)
        } catch {
            startError = "Couldn't start workout: \(error.localizedDescription)"
        }
    }

    private func swapWorkout() {
        guard let settings else { return }
        settings.lastCompletedWorkoutType = nextWorkoutType
        weightAdjustments = [:]
        try? modelContext.save()
    }
```

- [ ] **Step 4: Add accessibility identifiers to the swap button**

In `swapWorkoutButton`, add `.accessibilityIdentifier("swapWorkoutButton")` right after `.buttonStyle(.plain)`:

```swift
    private var swapWorkoutButton: some View {
        Button {
            swapWorkout()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 34, height: 34)
                .overlay(
                    Circle().stroke(Theme.borderStrong, lineWidth: 1)
                )
                .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("swapWorkoutButton")
        .disabled(settings == nil)
    }
```

- [ ] **Step 5: Replace `NextLiftRow`**

Replace the whole `NextLiftRow` struct with:

```swift
private struct NextLiftRow: View {
    let exercise: Exercise
    let config: UserExerciseConfig
    let unit: MeasurementUnit
    let targetWeight: Double
    let delta: Double
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    private var plates: PlateMath {
        PlateCalculator.plates(
            for: targetWeight,
            barWeight: PlateCalculator.barWeight(for: unit),
            available: PlateCalculator.plateSet(for: unit)
        )
    }

    /// "+N" ahead of last completed weight, "−N" behind it, "HOLD" if unchanged.
    private var deltaLabel: (text: String, color: Color) {
        if delta == 0 {
            return ("HOLD", Theme.textMuted)
        }
        if delta > 0 {
            return ("+\(delta.formatted(.number.precision(.fractionLength(0...1))))", Theme.accentText)
        }
        return ("−\(abs(delta).formatted(.number.precision(.fractionLength(0...1))))", Theme.warn)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.name)
                    .font(Theme.Font.title(19))
                    .foregroundStyle(Theme.textPrimary)
                MetaLabel(
                    text: "\(config.setCount) × \(config.repsPerSet) · \(plates.shortDescription) \(!plates.perSide.isEmpty ? "per side" : "")",
                    color: Theme.textDim
                )
                .tracking(1.2)
            }
            Spacer()
            HStack(spacing: 10) {
                StepButton(symbol: "−", action: onDecrement)
                    .accessibilityIdentifier("weightDecrement-\(exercise.name)")
                VStack(alignment: .trailing, spacing: 3) {
                    Text(targetWeight.formatted(.number.precision(.fractionLength(0...1))))
                        .font(Theme.Font.numeric(24))
                        .foregroundStyle(Theme.textPrimary)
                    Text(deltaLabel.text)
                        .font(Theme.Font.label())
                        .foregroundStyle(deltaLabel.color)
                }
                StepButton(symbol: "+", action: onIncrement)
                    .accessibilityIdentifier("weightIncrement-\(exercise.name)")
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}
```

`StepButton` is the existing internal component defined in `SettingsView.swift` (`symbol:`/`action:` init) — no new component needed.

- [ ] **Step 6: Run the UI tests to verify they pass**

Run: `cd 5x5ive && xcodebuild test -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:5x5iveUITests/_x5iveUITests/testAdjustingWeightUpdatesDisplayAndDeltaLiveWithoutPersisting -only-testing:5x5iveUITests/_x5iveUITests/testStartingWorkoutBakesInTheAdjustedWeight`
Expected: PASS

- [ ] **Step 7: Run the full existing UI test suite to check for regressions**

Run: `cd 5x5ive && xcodebuild test -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:5x5iveUITests`
Expected: PASS — in particular `testStartingWorkoutOpensActiveSessionWithFirstLiftExpanded` and `testCancelingWorkoutReturnsToTodayTab`, which start a workout with no adjustment made (default `weightAdjustments: [:]` must behave exactly as `startWorkout(in:)` did before).

- [ ] **Step 8: Commit**

```bash
git add 5x5ive/5x5ive/TodayView.swift
git commit -m "Add inline weight adjust with live delta to TodayView"
```

---

### Task 5: Full regression pass

**Files:** none (verification only)

- [ ] **Step 1: Run the SwoleData package suite**

Run: `cd SwoleData && swift test`
Expected: PASS, all tests.

- [ ] **Step 2: Run the full app UI test suite**

Run: `cd 5x5ive && xcodebuild test -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'`
Expected: PASS, all tests.

- [ ] **Step 3: Manual check in the simulator**

Launch the app (Debug config), on TodayView:
- Tap `+` a few times on a lift, confirm the weight and delta both update immediately and plates recompute.
- Tap `−` past the starting weight, confirm it floors at 0 rather than going negative.
- Tap the swap button, confirm the newly-shown workout's lifts have no leftover adjustment.
- Adjust a weight, start the workout, confirm the exercise's first set reflects the adjusted weight.
