# 5x5 Workout Tracker — DB Schema Design

## Context

Project Swole is an iPhone app tracking a standardized 5x5 strength program:

- **Workout A**: Squat, Bench Press, Barbell Row — 5 sets x 5 reps each
- **Workout B**: Squat, Overhead Press, Deadlift — 5 sets x 5 reps, except Deadlift which is 1 set x 5 reps
- Workouts alternate A/B/A, B/A/B, ...

Data is local-only for now (no backend). A backend API is planned for later, so the
schema is designed to be storage-agnostic (portable to a relational or NoSQL store),
not tied to SwiftData's modeling conventions, even though SwiftData is the initial
implementation target.

## Goals

- Model the 5x5 program (exercises, sets, reps, weight) faithfully.
- Support classic StrongLifts-style progressive overload: add weight on success,
  deload after repeated failure.
- Keep exercise definitions global/shared, while letting a user customize their own
  weights, increments, and deload rules per exercise.
- Avoid redundant/cacheable state that can drift out of sync — derive current
  weight and fail streak from workout history rather than storing a separate
  mutable "current state" table.
- Design so a `userId` column can be added later (multi-user backend) without
  reshaping the schema.

## Entities

### Exercise (global catalog)

Seeded once, shared by all users. Represents the fixed lift definitions.

| Field | Type | Notes |
|---|---|---|
| id | identifier | |
| name | string | Squat, Bench Press, Overhead Press, Deadlift, Barbell Row |
| defaultSetCount | int | suggestion only, e.g. 5 (1 for Deadlift) |
| defaultRepsPerSet | int | suggestion only, e.g. 5 |

### UserExerciseConfig (per-user override)

One per (user, Exercise). This is what progression logic actually reads from —
`Exercise` itself is never mutated per-user. Auto-created with "standard" 5x5
defaults when a user is set up, editable afterward.

| Field | Type | Notes |
|---|---|---|
| exerciseId | FK -> Exercise | |
| startingWeight | number | used only when no prior ExerciseLog exists |
| weightIncrement | number | e.g. +5 lb (Squat/Bench/OHP/Row), +10 lb (Deadlift) |
| setCount | int | defaults from Exercise.defaultSetCount |
| repsPerSet | int | defaults from Exercise.defaultRepsPerSet |
| deloadThreshold | int | consecutive fails before deload; default 3 (recommend 2, 3, or 5) |
| deloadPercentage | number | weight cut on deload; default 0.10 (recommend 0.05, 0.10, or 0.15) |

### WorkoutTemplateExercise (per-user day assignment)

Which exercises appear on Workout A vs B, and in what order. Lets a user
customize their split later without changing the Exercise catalog.

| Field | Type | Notes |
|---|---|---|
| workoutType | enum (A, B) | |
| exerciseId | FK -> Exercise | |
| order | int | display/execution order within the day |

### WorkoutSession (one gym visit)

| Field | Type | Notes |
|---|---|---|
| date | date | |
| workoutType | enum (A, B) | |

### ExerciseLog (one exercise performed within a session)

| Field | Type | Notes |
|---|---|---|
| sessionId | FK -> WorkoutSession | |
| exerciseId | FK -> Exercise | |
| targetWeight | number | snapshot of the weight attempted this session |
| targetReps | number | snapshot of reps-per-set target this session |

`succeeded` is **derived, not stored**: true if every related `SetLog.repsCompleted`
equals `targetReps`.

### SetLog (one work set)

Only work sets are tracked; warm-up sets are not logged.

| Field | Type | Notes |
|---|---|---|
| exerciseLogId | FK -> ExerciseLog | |
| setNumber | int | 1-based |
| repsCompleted | int | |

### UserSettings (singleton)

| Field | Type | Notes |
|---|---|---|
| unit | enum (lb, kg) | |
| lastCompletedWorkoutType | enum (A, B), nullable | drives auto-alternation |

All entities implicitly belong to a single local user for now. Adding a `userId`
column to each table is the only change needed to support multiple users/a backend
later — no structural reshaping.

## Derived Logic (application code, not schema)

**Next target weight for an exercise:**

1. Find the most recent `ExerciseLog` for that exercise, across all sessions,
   ordered by session date descending.
2. If none exists: use `UserExerciseConfig.startingWeight`.
3. If the most recent log succeeded: `targetWeight + weightIncrement`.
4. If it failed: walk backward through history counting the consecutive-fail
   streak (including this one).
   - If streak >= `deloadThreshold`: `targetWeight * (1 - deloadPercentage)`,
     and the streak effectively resets after the deload.
   - Otherwise: repeat the same `targetWeight`.

**Next workout day:** the opposite of `UserSettings.lastCompletedWorkoutType`
(A -> B, B -> A). If null (first-ever session), either day is a valid start
(app can default to A).

## Explicitly Out of Scope (for this spec)

- Warm-up set tracking.
- Body weight / measurements tracking.
- Backend sync / multi-device / multi-user auth.
- Auto-detecting unit conversion when a user switches lb <-> kg (existing
  increments/weights are not auto-converted).
