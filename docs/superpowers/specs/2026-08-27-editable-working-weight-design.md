# Editable Working Weight — Design

## Context

Two related bugs reported by the user:

1. Settings' "Working weights" section shows `UserExerciseConfig.startingWeight`.
   That field is only consulted by `ProgressionCalculator.nextTargetWeight` when
   an exercise has **no** logged history — after the first session ever, the
   calculator chains off `lastLog.targetWeight` instead. So finishing a workout
   never updates `startingWeight` (Settings goes stale), and editing
   `startingWeight` in Settings has no effect once history exists (silently
   ignored).
2. `ExerciseDetailSheet`'s "Edit weight" button navigates to the global
   `SettingsView` instead of touching the current session's `ExerciseLog`. There
   is no way to adjust the weight of an exercise already in progress.

This spec supersedes the non-goal called out in
`2026-08-27-active-workout-session-design.md` ("Editing target weight/reps
mid-session ... may be added later") for weight specifically. Reps remain
out of scope here.

## Goals

- Settings' working-weight display always reflects the actual current
  computed weight for each exercise, with no explicit sync step required.
- Editing the weight in Settings changes what the *next* started session
  uses for that exercise.
- The active workout screen lets you edit an exercise's weight directly,
  affecting only the in-progress session's `ExerciseLog`.

## Non-Goals

- Editing reps mid-session (unchanged from the existing spec).
- Editing weight on a finished (read-only) session — `ExerciseDetailSheet` is
  only ever presented from `ActiveWorkoutView`, so this doesn't arise.
- Per-set weight (drop sets, different weight per set within one exercise).
  `ExerciseLog.targetWeight` remains a single value for the whole exercise.
- Retroactively adjusting `volume` math for sets logged before a mid-workout
  weight edit — `ExerciseLog.volume` uses the log's current `targetWeight` for
  all its sets today already; this spec doesn't change that behavior.

## Data Model Changes

### `UserExerciseConfig`

| Field | Change |
|---|---|
| `weightOverride: Double?` | **new**, default `nil`. A one-shot manual override consumed the next time a session is started for this exercise. Additive optional property — lightweight SwiftData migration, no migration plan needed. |

## Behavior Changes

### `ProgressionCalculator.nextTargetWeight`

Check the override first, before the existing history-chain logic:

```swift
public static func nextTargetWeight(for exercise: Exercise, config: UserExerciseConfig, in context: ModelContext) throws -> Double {
    if let override = config.weightOverride { return override }
    // ...existing logic unchanged
}
```

Existing tests are unaffected since `weightOverride` defaults to `nil`.

### `WorkoutSessionService.insertExerciseLog`

After computing `targetWeight` (which may be the override), clear it:

```swift
config.weightOverride = nil
```

so it doesn't leak into future sessions once it's been consumed into log
history.

### `SettingsView` (`WeightRow`)

Displayed value becomes:

```swift
config.weightOverride ?? (try? ProgressionCalculator.nextTargetWeight(for: exercise, config: config, in: context)) ?? config.startingWeight
```

This is why Settings self-heals after every workout: once the override is
consumed and cleared, the row falls through to the live computed value, which
already reflects the just-finished session's `targetWeight`.

The +/- steppers write to `config.weightOverride`, seeded from the
currently-displayed value (not from `startingWeight` directly).

### `ExerciseDetailSheet`

- Remove the "Edit weight" button (currently a `NavigationLink` to
  `SettingsView`; touches nothing on the current log).
- The header's static weight `Text` becomes a stepper (same `StepButton`
  visual style used in `SettingsView`/`ExerciseCard`), bound directly to
  `log.targetWeight`, step size `config.weightIncrement`. Writes call
  `modelContext.save()` same as the existing note/warmup actions in this file.
- `actionRow` keeps just the "Done" button.

## Testing

- `SwoleDataTests/ProgressionCalculatorTests.swift`: new case — override set →
  `nextTargetWeight` returns override regardless of history.
- `SwoleDataTests/WorkoutSessionServiceTests.swift`: new case — starting a
  workout with an override consumes it (`config.weightOverride == nil` after
  `startWorkout`, and the inserted log's `targetWeight` equals the override
  that was set).
- No new UI tests planned (matches existing project convention — UI is
  manually verified in Simulator per `CLAUDE.md`/skill conventions, no XCUITest
  coverage added for cosmetic controls elsewhere in the app).
