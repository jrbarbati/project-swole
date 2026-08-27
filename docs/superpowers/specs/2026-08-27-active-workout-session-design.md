# Active Workout Session — UI & Data Design

## Context

The data layer (`SwoleData`) already models the 5x5 program: `Exercise`,
`UserExerciseConfig`, `WorkoutTemplateExercise`, `WorkoutSession`, `ExerciseLog`,
`SetLog`, `UserSettings`, plus `ProgressionCalculator` (next target weight, fail
streak/deload) and `WorkoutScheduler` (A/B alternation). See
`docs/superpowers/specs/2026-08-27-5x5-tracker-db-schema-design.md`.

The `5x5ive` app target has no real UI yet (`ContentView` is a placeholder) and
nothing in the schema currently creates a session, records reps during a workout,
or marks a session "done." This spec covers building that full loop:

- Starting a workout (auto-computes the day's exercises/weights from the
  template + progression logic)
- Editing rep counts for any set during an active session
- A rest timer that reacts to each set's success/failure
- Finishing a workout, which permanently locks it from further edits
- Canceling an active workout (delete it, as if it never happened)
- A minimal home screen and read-only history of past sessions

## Goals

- Let a user run an entire workout session end-to-end: start → log every set →
  finish, with correct weights/reps computed automatically.
- Make "finished" permanent — no editing a session once `finishedAt` is set,
  anywhere in the UI.
- Make logging reps fast (single-tap, no keyboard) and forgiving (freely
  correctable while the session is active).
- Support relaunching the app mid-workout without losing progress.

## Non-Goals

- Editing target weight/reps mid-session (locked once the session starts —
  may be added later).
- Editing or un-finishing a session after it's been finished.
- Warm-up set tracking, body-weight tracking, backend sync (per the DB schema
  spec's existing out-of-scope list).
- Persisting rest-timer state across app relaunch (advisory only, resets on
  relaunch — not a data-integrity concern).

## Data Model Changes

### `WorkoutSession`

| Field | Change |
|---|---|
| `date: Date` | renamed → `startedAt: Date`, set when **Start Workout** is tapped |
| `finishedAt: Date?` | **new**. `nil` = active/unfinished. Non-nil = permanently locked. This is the *only* "is it locked" signal — no separate boolean. |

### `ExerciseLog`

| Field | Change |
|---|---|
| `order: Int` | **new**. Snapshotted from `WorkoutTemplateExercise.order` when the session is created. SwiftData to-many relationship arrays don't guarantee stored order, and the active-workout carousel needs a stable exercise sequence, so this must be explicit rather than inferred at render time from the template. |

### `SetLog`

| Field | Change |
|---|---|
| `repsCompleted: Int` | → `repsCompleted: Int?`. `nil` = "not started" (distinct from `0` = "attempted, got zero reps"). Drives the tap-cycle button (see below). |

`ExerciseLog.succeeded` updates to treat `nil` as not meeting target:
`!sets.isEmpty && sets.allSatisfy { ($0.repsCompleted ?? -1) >= targetReps }`.
Sets are pre-created (never empty) as soon as the session starts, so this stays
correctly `false` until every set has a real value.

### `UserExerciseConfig`

| Field | Change |
|---|---|
| `restSecondsOnSuccess: Int` | **new**, default `90` |
| `restSecondsOnFail: Int` | **new**, default `180` |

Per-exercise (not global on `UserSettings`), so e.g. Deadlift could later get a
longer rest without affecting other lifts. `StandardSeed` seeds both fields to
`90`/`180` for all five seeded exercises.

### Migration

These are renames, a type change (`Int` → `Int?`), and new fields on existing
persisted models — not additive-only. This needs a `SchemaMigrationPlan` /
`VersionedSchema` (SwiftData's lightweight migration), not just editing the
`@Model` classes in place, so an existing local store upgrades instead of
crashing or silently losing data.

## Session Lifecycle Logic (new `SwoleData` code)

New enum/type, e.g. `WorkoutSessionService`:

- **`activeSession(in context:) -> WorkoutSession?`** — fetches the session
  with `finishedAt == nil`. Invariant: at most one exists at a time, enforced
  by only ever creating a new one when this returns `nil`.

- **`startWorkout(in context:) throws -> WorkoutSession`**:
  1. `WorkoutScheduler.nextWorkoutType(after: userSettings)`
  2. Fetch that day's `WorkoutTemplateExercise` rows, sorted by `order`
  3. For each: compute `targetWeight` via
     `ProgressionCalculator.nextTargetWeight`, `targetReps` from
     `UserExerciseConfig.repsPerSet`; create the `ExerciseLog` with the
     snapshotted `order`; pre-create `config.setCount` `SetLog` rows
     (`repsCompleted: nil`)
  4. Create the `WorkoutSession` with `startedAt = .now`, `finishedAt = nil`

- **`finishWorkout(_ session:, in context:) throws`** — coerces any remaining
  `nil` `repsCompleted` to `0`, sets `finishedAt = .now`, updates
  `UserSettings.lastCompletedWorkoutType = session.workoutType`, saves. Caller
  shows the confirmation alert *before* calling this — this function just does
  the finish, unconditionally.

- **`cancelWorkout(_ session:, in context:) throws`** — only valid while
  `finishedAt == nil`. Deletes the `WorkoutSession`, which cascades to its
  `ExerciseLog`s and `SetLog`s via the existing cascade delete rules. Does
  **not** touch `UserSettings.lastCompletedWorkoutType` — canceling leaves the
  next `startWorkout` computing the same workout type as if the cancelled
  session never existed.

## Screens & Navigation

- **`ContentView`** (root) — checks `WorkoutSessionService.activeSession` on
  appear. If one exists, goes straight into `ActiveWorkoutView(session:)`.
  Otherwise shows `HomeView`. This is what makes mid-workout app relaunch
  "just resume."

- **`HomeView`** — shows the next workout type
  (`WorkoutScheduler.nextWorkoutType`) and its exercise list, a **Start
  Workout** button (calls `startWorkout`, navigates into
  `ActiveWorkoutView`), and a link into `HistoryListView`.

- **`HistoryListView`** — finished sessions (`finishedAt != nil`), newest
  first: date, workout type, per-exercise pass/fail summary (e.g. "Squat ✓ ·
  Bench ✗ · Row ✓"). Tapping a row opens `HistorySessionDetailView`.

- **`HistorySessionDetailView`** — same visual layout as the active carousel
  (exercise name, weight × reps, per-set values) but fully read-only: no
  buttons, no tap-cycling, no rest timer, no Finish/Cancel.

- **`ActiveWorkoutView(session:)`** — the one-exercise-at-a-time carousel.
  Local `@State` tracks which exercise index is showing; on open, defaults to
  the first exercise with any not-started set (or the last exercise if
  everything's already logged). Prev/Next arrows navigate between exercises,
  disabled at the ends. Nav bar has **Finish Workout** and **Cancel Workout**,
  both always enabled while the session is active.

## Active Workout Mechanics

**Per-set button.** One button per `SetLog` (ordered by `setNumber`), showing
`—` when `repsCompleted == nil`, else the number. Tapping cycles:

```
not started → target → target-1 → … → 1 → 0 → not started → target → …
```

Each set's button is independent — no bulk "mark all sets" control.

**Rest timer.** Fires *only* on the tap that transitions a set from `nil`
into a value — not on later taps that cycle that same set to a different
non-nil value (overshoot corrections), and not on edits made after the fact
by navigating back to an earlier exercise... except: if a set gets cycled all
the way back around to `nil` ("reset"), any timer running for it is
cancelled, the set reverts to "not started," and the *next* `nil → value` tap
on it starts a fresh timer. Net effect: the timer always tracks "does this
set currently have a freshly-committed value," which is simple to implement
and matches what the user actually wants rest for.

Duration: `config.restSecondsOnSuccess` if the value `>= targetReps`, else
`config.restSecondsOnFail`. Displayed as an advisory (non-blocking) countdown
— the next set's button stays tappable the whole time; the timer is a
suggestion, not a gate.

**Exercise transition (last set of an exercise).** Instead of a rest timer,
the `nil → value` tap on an exercise's *final* set shows an interstitial:
"Nice work on Squat — ready for Bench Press?" with a Continue button that
advances the carousel. On the last exercise of the session, the message
becomes "Workout complete — tap Finish Workout" instead (nothing to advance
to). Same trigger rule as the rest timer: only the `nil → value` tap fires
it, not later corrections.

**Finish Workout.** Tapping shows a confirmation alert if any set in the
session is still `nil` ("2 sets not logged — finish anyway?"), since this is
about to become permanent. Confirming calls `finishWorkout` (coerces
remaining `nil`s to `0`, sets `finishedAt`, updates `UserSettings`), then
pops back to `HomeView`. From that point the session is reachable only via
`HistorySessionDetailView`, and only ever read-only.

**Cancel Workout.** Tapping shows a confirmation alert (destructive — this
deletes data). Confirming calls `cancelWorkout` and pops back to `HomeView`.
No trace of the session remains.

## Testing

`SwoleData` unit tests (Swift Testing, in-memory `ModelContext`, following the
existing `ProgressionCalculatorTests` pattern):

- `startWorkout` creates the correct exercises (in template order), weights
  (via `ProgressionCalculator`), and set counts (pre-created as `nil`).
- `finishWorkout` coerces remaining `nil`s to `0`, sets `finishedAt`, and
  updates `lastCompletedWorkoutType`.
- `cancelWorkout` deletes the session and cascades correctly, and leaves
  `lastCompletedWorkoutType` untouched.
- `activeSession` returns `nil`/non-nil correctly, and never returns more
  than one session.
- Migration test: open a store built with the old schema shape and confirm
  it upgrades cleanly (renamed/new fields land with the right defaults).

UI-level logic that's cleanly extractable as pure functions — the tap-cycle
sequence (`nextCycleValue(current:target:) -> Int?`) and the
timer-vs-interstitial trigger rule (does this transition count as "first
commit"?) — should be pulled into `SwoleData` or a small testable helper and
unit tested directly, rather than relying on UI tests.
