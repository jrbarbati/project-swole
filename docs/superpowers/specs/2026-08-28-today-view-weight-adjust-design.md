# TodayView: inline weight adjust + live delta

## Problem

1. `NextLiftRow`'s delta label (`+5` / `HOLD` / `DELOAD`) is derived from `failStreak`/`config`, not from the weight actually shown. It doesn't move if the shown weight changes.
2. There's no way to quickly nudge a lift's planned weight for today's session from TodayView. The only adjustment path is Settings (`WeightRow`), which writes `config.weightOverride` straight to the persistent store.

## Requirements

- Add `−`/`+` buttons flanking the target weight in each `NextLiftRow`, stepping by `config.weightIncrement`, floored at 0.
- The delta label below the weight must reflect the *displayed* weight, live, as the user taps `−`/`+`.
- Adjustments are local to the TodayView screen: they must not write to `UserExerciseConfig` or any other persisted model until the user taps **Start Workout**.
- Tapping **Swap Workout** discards any pending adjustments.
- Starting the workout bakes the adjusted weight into that session's `ExerciseLog` (same place `nextTargetWeight`/`config.weightOverride` are baked in today).

## Design

### Local adjustment state (TodayView)

```swift
@State private var weightAdjustments: [PersistentIdentifier: Double] = [:]
```

Keyed by `Exercise.persistentModelID`. A helper resolves the weight to display:

```swift
private func displayWeight(for exercise: Exercise, config: UserExerciseConfig) -> Double {
    weightAdjustments[exercise.persistentModelID] ?? targetWeight(for: exercise, config: config)
}
```

`NextLiftRow` takes this resolved weight (as it does today) plus `onIncrement`/`onDecrement` closures. The row itself stays presentation-only — it doesn't know about the adjustment dictionary.

### Delta label

Today's `deltaLabel` in `NextLiftRow` is replaced with a signed numeric diff against the last *actual* completed weight for the exercise:

```swift
// ProgressionCalculator+Redesign.swift
public static func lastCompletedWeight(for exercise: Exercise, in context: ModelContext) throws -> Double? {
    try recentLogs(for: exercise, limit: 1, in: context).last?.targetWeight
}
```

TodayView resolves a baseline per exercise (`lastCompletedWeight(...) ?? config.startingWeight`) and passes `(displayWeight - baseline)` into `NextLiftRow` as the delta. Label logic becomes:

- `0` → `"HOLD"`, muted color
- `> 0` → `"+N"`, accent color
- `< 0` → `"−N"`, warn color

No more special-cased `DELOAD` string — a deload shows up as a negative number like any other decrease, since it's just baseline vs. displayed weight.

### Buttons

Reuse the existing `StepButton` (defined in SettingsView.swift, internal to the app target) rather than a new component. Row layout becomes:

```
[ − ]   Exercise Name              [ − ]  120.0
        sets × reps · plates              +10     [ + ]
                                    [ + ]
```

(i.e. `StepButton`s flank the existing trailing weight/delta `VStack`.)

Tapping `−`/`+` writes `max(0, displayWeight ± config.weightIncrement)` into `weightAdjustments[exercise.persistentModelID]`.

### Discarding on swap

`swapWorkout()` clears the dict after flipping `lastCompletedWorkoutType`:

```swift
private func swapWorkout() {
    guard let settings else { return }
    settings.lastCompletedWorkoutType = nextWorkoutType
    weightAdjustments = [:]
    try? modelContext.save()
}
```

### Baking into the session

`WorkoutSessionService.startWorkout` gains an optional param:

```swift
public static func startWorkout(
    in context: ModelContext,
    weightOverrides: [PersistentIdentifier: Double] = [:]
) throws -> WorkoutSession
```

`insertExerciseLog` resolves target weight as:

```swift
let targetWeight = weightOverrides[exercise.persistentModelID]
    ?? (try ProgressionCalculator.nextTargetWeight(for: exercise, config: config, in: context))
config.weightOverride = nil
```

`config.weightOverride` is still cleared unconditionally (existing one-shot Settings mechanism), whether or not a TodayView override was used, so a stale Settings-set override never leaks into a later session.

TodayView's `startWorkout()` builds the dict from `weightAdjustments` (already keyed by `persistentModelID`) and passes it straight through.

## Files touched

- `5x5ive/5x5ive/TodayView.swift` — adjustment state, button wiring, delta computation, swap-discard.
- `SwoleData/Sources/SwoleData/ProgressionCalculator+Redesign.swift` — new `lastCompletedWeight` helper.
- `SwoleData/Sources/SwoleData/WorkoutSessionService.swift` — `weightOverrides` param on `startWorkout`.

## Testing

- Unit: `lastCompletedWeight` returns `nil` with no finished logs, returns the most recent finished log's `targetWeight` otherwise.
- Unit: `WorkoutSessionService.startWorkout` uses a supplied override over both the computed value and a set `config.weightOverride`, and still clears `config.weightOverride` after.
- Manual: tap `−`/`+` in TodayView, confirm weight and delta both update live, plates recompute; swap workout and confirm adjustments reset; start workout and confirm the adjusted weight lands in the session's `ExerciseLog`.

## Out of scope

- The "held" note (`holdNote`, e.g. "ROW HELD — 2 MISSES AT 110") keeps using the unadjusted calculated weight — it communicates hold/deload status, not the user's in-progress edit.
