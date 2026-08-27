# Editable Working Weight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Settings' stale "Working weights" display, make Settings edits actually affect the next workout, and let a user edit an exercise's weight directly on the active workout screen.

**Architecture:** Add a one-shot `weightOverride: Double?` to `UserExerciseConfig`. `ProgressionCalculator.nextTargetWeight` checks it first; `WorkoutSessionService` consumes (clears) it when a session starts. Settings displays the live computed weight (self-healing after every workout) and writes edits to the override. `ExerciseDetailSheet` gets a weight stepper wired straight to the in-progress session's `ExerciseLog.targetWeight`.

**Tech Stack:** Swift, SwiftData, SwiftUI, Swift Testing (`@Test`/`#expect`), local Swift package `SwoleData` consumed by the `5x5ive` Xcode app target.

Spec: `docs/superpowers/specs/2026-08-27-editable-working-weight-design.md`

---

### Task 1: `weightOverride` field on `UserExerciseConfig`

**Files:**
- Modify: `SwoleData/Sources/SwoleData/UserExerciseConfig.swift`
- Test: `SwoleData/Tests/SwoleDataTests/UserExerciseConfigTests.swift`

- [ ] **Step 1: Extend the existing test to assert the new field**

In `SwoleData/Tests/SwoleDataTests/UserExerciseConfigTests.swift`, add one assertion to the end of `userExerciseConfigLinksToItsExercise`:

```swift
@Test func userExerciseConfigLinksToItsExercise() throws {
    let container = try ModelContainer(
        for: Exercise.self, UserExerciseConfig.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    context.insert(UserExerciseConfig(
        exercise: squat,
        startingWeight: 45,
        weightIncrement: 5,
        setCount: 5,
        repsPerSet: 5,
        deloadThreshold: 3,
        deloadPercentage: 0.10
    ))
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<UserExerciseConfig>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.exercise?.name == "Squat")
    #expect(fetched.first?.startingWeight == 45)
    #expect(fetched.first?.weightIncrement == 5)
    #expect(fetched.first?.deloadThreshold == 3)
    #expect(fetched.first?.deloadPercentage == 0.10)
    #expect(fetched.first?.weightOverride == nil)
}
```

Only the final `#expect(fetched.first?.weightOverride == nil)` line is new.

- [ ] **Step 2: Run the test to verify it fails to compile**

Run: `cd SwoleData && swift test --filter userExerciseConfigLinksToItsExercise`
Expected: build error — `value of type 'UserExerciseConfig' has no member 'weightOverride'`

- [ ] **Step 3: Add the field**

In `SwoleData/Sources/SwoleData/UserExerciseConfig.swift`, add the property and initialize it to `nil` (don't add it as an `init` parameter — it's never set at construction time, only mutated later):

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
    /// One-shot manual weight nudge for the next session started for this
    /// exercise. Consumed (set back to `nil`) by `WorkoutSessionService`
    /// once a session picks it up.
    public var weightOverride: Double?

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
        self.weightOverride = nil
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd SwoleData && swift test --filter userExerciseConfigLinksToItsExercise`
Expected: `Test run with 1 test in 1 suite passed`

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/UserExerciseConfig.swift SwoleData/Tests/SwoleDataTests/UserExerciseConfigTests.swift
git commit -m "Add one-shot weightOverride field to UserExerciseConfig"
```

---

### Task 2: `ProgressionCalculator` honors the override

**Files:**
- Modify: `SwoleData/Sources/SwoleData/ProgressionCalculator.swift:35-51`
- Test: `SwoleData/Tests/SwoleDataTests/ProgressionCalculatorTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `SwoleData/Tests/SwoleDataTests/ProgressionCalculatorTests.swift`:

```swift
@Test func nextTargetWeightUsesOverrideRegardlessOfHistory() throws {
    let context = try makeInMemoryContext()

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let config = UserExerciseConfig(
        exercise: squat, startingWeight: 45, weightIncrement: 5,
        setCount: 5, repsPerSet: 5, deloadThreshold: 3, deloadPercentage: 0.10
    )
    context.insert(config)

    let session = WorkoutSession(startedAt: Date(), workoutType: .a)
    context.insert(session)

    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 135, targetReps: 5)
    context.insert(log)

    for n in 1...5 {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: 5))
    }
    try context.save()

    // Without an override, history says 140 (135 + increment, last session succeeded).
    config.weightOverride = 225
    try context.save()

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 225)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SwoleData && swift test --filter nextTargetWeightUsesOverrideRegardlessOfHistory`
Expected: FAIL — `#expect(next == 225)` fails because `next` is `140` (the override is defined but not yet consulted).

- [ ] **Step 3: Implement**

In `SwoleData/Sources/SwoleData/ProgressionCalculator.swift`, change:

```swift
    public static func nextTargetWeight(for exercise: Exercise, config: UserExerciseConfig, in context: ModelContext) throws -> Double {
        let logs = try sortedLogs(for: exercise, in: context)
        guard let lastLog = logs.first else {
            return config.startingWeight
        }
```

to:

```swift
    public static func nextTargetWeight(for exercise: Exercise, config: UserExerciseConfig, in context: ModelContext) throws -> Double {
        if let override = config.weightOverride {
            return override
        }

        let logs = try sortedLogs(for: exercise, in: context)
        guard let lastLog = logs.first else {
            return config.startingWeight
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SwoleData && swift test --filter ProgressionCalculatorTests`
Expected: all `ProgressionCalculatorTests` cases pass (6 tests: the 5 pre-existing plus the new one), 0 failures.

- [ ] **Step 5: Commit**

```bash
git add SwoleData/Sources/SwoleData/ProgressionCalculator.swift SwoleData/Tests/SwoleDataTests/ProgressionCalculatorTests.swift
git commit -m "Make nextTargetWeight honor a manual weightOverride"
```

---

### Task 3: `WorkoutSessionService` consumes the override on session start

**Files:**
- Modify: `SwoleData/Sources/SwoleData/WorkoutSessionService.swift:52-72`
- Test: `SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift`:

```swift
@Test func startWorkoutConsumesWeightOverrideIntoTheLogAndClearsIt() throws {
    let context = try makeSeededContext()

    let squat = try context.fetch(FetchDescriptor<Exercise>())
        .first { $0.name == "Squat" }
    let config = try context.fetch(FetchDescriptor<UserExerciseConfig>())
        .first { $0.exercise?.persistentModelID == squat?.persistentModelID }
    config?.weightOverride = 225
    try context.save()

    let session = try WorkoutSessionService.startWorkout(in: context)

    let squatLog = session.exerciseLogs.first { $0.exercise?.name == "Squat" }
    #expect(squatLog?.targetWeight == 225)
    #expect(config?.weightOverride == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SwoleData && swift test --filter startWorkoutConsumesWeightOverrideIntoTheLogAndClearsIt`
Expected: FAIL — `squatLog?.targetWeight` is `45` (the override isn't read yet), not `225`.

- [ ] **Step 3: Implement**

In `SwoleData/Sources/SwoleData/WorkoutSessionService.swift`, change:

```swift
    private static func insertExerciseLog(
        for exercise: Exercise,
        config: UserExerciseConfig,
        order: Int,
        in session: WorkoutSession,
        context: ModelContext
    ) throws {
        let targetWeight = try ProgressionCalculator.nextTargetWeight(for: exercise, config: config, in: context)
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

to:

```swift
    private static func insertExerciseLog(
        for exercise: Exercise,
        config: UserExerciseConfig,
        order: Int,
        in session: WorkoutSession,
        context: ModelContext
    ) throws {
        let targetWeight = try ProgressionCalculator.nextTargetWeight(for: exercise, config: config, in: context)
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

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SwoleData && swift test --filter WorkoutSessionServiceTests`
Expected: all `WorkoutSessionServiceTests` cases pass (6 tests: the 5 pre-existing plus the new one), 0 failures.

- [ ] **Step 5: Run the full SwoleData test suite**

Run: `cd SwoleData && swift test`
Expected: all tests across the package pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add SwoleData/Sources/SwoleData/WorkoutSessionService.swift SwoleData/Tests/SwoleDataTests/WorkoutSessionServiceTests.swift
git commit -m "Consume and clear weightOverride when a workout session starts"
```

---

### Task 4: Settings shows the live weight and edits write the override

**Files:**
- Modify: `5x5ive/5x5ive/SettingsView.swift:168-223`

No unit tests in this task — this is a SwiftUI view with no existing UI test harness in the project (matches the spec's testing section). Verified by building the app target and a manual Simulator check at the end of Task 5.

- [ ] **Step 1: Make `StepButton` reusable outside this file**

In `5x5ive/5x5ive/SettingsView.swift`, change:

```swift
private struct StepButton: View {
```

to:

```swift
struct StepButton: View {
```

(No other change to that struct — dropping `private` makes it visible to other files in the same app target, which Task 5 needs.)

- [ ] **Step 2: Rewrite `WeightRow` to show the live computed weight and edit the override**

Replace the whole `WeightRow` struct:

```swift
private struct WeightRow: View {
    let config: UserExerciseConfig
    let unit: MeasurementUnit
    let onChange: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(config.exercise?.name ?? "")
                    .font(Theme.Font.title(16))
                    .foregroundStyle(Theme.textPrimary)
                MetaLabel(text: "+\(config.weightIncrement.formatted()) \(unit.rawValue) per session",
                          color: Theme.textDim)
                    .tracking(1.2)
            }
            Spacer()
            HStack(spacing: 10) {
                StepButton(symbol: "−") {
                    config.startingWeight = max(0, config.startingWeight - config.weightIncrement)
                    onChange()
                }
                Text(config.startingWeight.formatted(.number.precision(.fractionLength(0...1))))
                    .font(Theme.Font.numeric(19))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44)
                StepButton(symbol: "+") {
                    config.startingWeight += config.weightIncrement
                    onChange()
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
```

with:

```swift
private struct WeightRow: View {
    let config: UserExerciseConfig
    let unit: MeasurementUnit
    let onChange: () -> Void

    @Environment(\.modelContext) private var modelContext

    /// The weight that will be used the next time this exercise's workout
    /// starts: the manual override if one is set, otherwise the same
    /// progression calculation the workout itself uses. Always live — no
    /// separate sync step needed after finishing a workout.
    private var currentWeight: Double {
        if let override = config.weightOverride { return override }
        guard let exercise = config.exercise else { return config.startingWeight }
        return (try? ProgressionCalculator.nextTargetWeight(for: exercise, config: config, in: modelContext))
            ?? config.startingWeight
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(config.exercise?.name ?? "")
                    .font(Theme.Font.title(16))
                    .foregroundStyle(Theme.textPrimary)
                MetaLabel(text: "+\(config.weightIncrement.formatted()) \(unit.rawValue) per session",
                          color: Theme.textDim)
                    .tracking(1.2)
            }
            Spacer()
            HStack(spacing: 10) {
                StepButton(symbol: "−") {
                    config.weightOverride = max(0, currentWeight - config.weightIncrement)
                    onChange()
                }
                Text(currentWeight.formatted(.number.precision(.fractionLength(0...1))))
                    .font(Theme.Font.numeric(19))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44)
                StepButton(symbol: "+") {
                    config.weightOverride = currentWeight + config.weightIncrement
                    onChange()
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
```

- [ ] **Step 3: Build the SwoleData package to catch typos early**

Run: `cd SwoleData && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add 5x5ive/5x5ive/SettingsView.swift
git commit -m "Show live working weight in Settings; edits write a one-shot override"
```

---

### Task 5: In-workout weight editing on `ExerciseDetailSheet`

**Files:**
- Modify: `5x5ive/5x5ive/ExerciseDetailSheet.swift:48-59` (header), `5x5ive/5x5ive/ExerciseDetailSheet.swift:121-149` (actionRow)

No unit tests in this task — same rationale as Task 4. Verified by building the app target and a manual Simulator check in Step 4 below.

- [ ] **Step 1: Replace the static weight `Text` in the header with a stepper**

In `5x5ive/5x5ive/ExerciseDetailSheet.swift`, change:

```swift
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(log.exercise?.name ?? "")
                .font(Theme.Font.display(26))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(log.targetWeight.formatted()) \(unit.rawValue.uppercased())")
                .font(Theme.Font.numeric(15))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.top, 20)
    }
```

to:

```swift
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(log.exercise?.name ?? "")
                .font(Theme.Font.display(26))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            weightStepper
        }
        .padding(.top, 20)
    }

    /// Edits `log.targetWeight` directly — this only ever affects the
    /// exercise log of the session already in progress, since this sheet is
    /// only ever presented from `ActiveWorkoutView`.
    private var weightStepper: some View {
        HStack(spacing: 10) {
            StepButton(symbol: "−") {
                log.targetWeight = max(0, log.targetWeight - (config?.weightIncrement ?? 5))
                try? modelContext.save()
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(log.targetWeight.formatted(.number.precision(.fractionLength(0...1))))
                    .font(Theme.Font.numeric(15))
                    .foregroundStyle(Theme.textMuted)
                Text(unit.rawValue.uppercased())
                    .font(Theme.Font.numeric(15))
                    .foregroundStyle(Theme.textMuted)
            }
            StepButton(symbol: "+") {
                log.targetWeight += (config?.weightIncrement ?? 5)
                try? modelContext.save()
            }
        }
    }
```

- [ ] **Step 2: Drop the "Edit weight" navigation button, keep just Done**

Change:

```swift
    private var actionRow: some View {
        HStack(spacing: 10) {
            NavigationLink {
                SettingsView()
            } label: {
                Text("Edit weight")
                    .font(Theme.Font.body(15))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .stroke(Theme.borderStrong, lineWidth: 1)
                    )
            }
            Button {
                save()
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.canvas)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
```

to:

```swift
    private var actionRow: some View {
        Button {
            save()
            dismiss()
        } label: {
            Text("Done")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.canvas)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 3: Build the app target**

Run (from `5x5ive/`): `xcodebuild -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | tail -40`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual Simulator smoke test**

1. Run: `xcrun simctl launch booted com.<yourbundleid>.5x5ive` — if unsure of the bundle ID, instead open the app via Xcode (`open 5x5ive.xcodeproj`, ⌘R) targeting the booted "iPhone 17 Pro Max" simulator.
2. Start a workout from Today. Confirm the weight header on an exercise card, when expanded, opens the exercise sheet via "More".
3. In the sheet, tap the new −/+ next to the weight. Confirm the number changes immediately and there's no "Edit weight" button anymore — just "Done".
4. Dismiss the sheet, back out to the exercise card — confirm the weight shown there now reflects the edit (same `log.targetWeight`).
5. Finish or cancel the workout, go to Settings → Working weights. Confirm the number shown matches what progression would compute next (bumped by the increment if you finished all sets successfully at the weight you just edited to).
6. From Settings, tap −/+ on a working weight, then start a new workout for that exercise (if `workoutType` rotation allows same-day retry, cancel and restart, or check via the exercise's log once started) — confirm the new session's exercise opens at the weight you set in Settings.

- [ ] **Step 5: Commit**

```bash
git add 5x5ive/5x5ive/ExerciseDetailSheet.swift
git commit -m "Let the active workout screen edit an exercise's weight directly"
```

---

### Task 6: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full SwoleData test suite**

Run: `cd SwoleData && swift test`
Expected: all tests pass, 0 failures (should include the 3 new tests from Tasks 1–3 plus all pre-existing ones).

- [ ] **Step 2: Build the app target one more time end-to-end**

Run (from `5x5ive/`): `xcodebuild -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | tail -40`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Confirm no other reference to the old "Edit weight" navigation remains**

Run: `grep -rn "Edit weight" 5x5ive/5x5ive/`
Expected: no output (the button was removed in Task 5 and never existed elsewhere).
