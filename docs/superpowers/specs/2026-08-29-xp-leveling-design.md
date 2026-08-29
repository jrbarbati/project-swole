# XP + leveling system

## Problem

No positive feedback loop tied to *finishing* workouts, hitting PRs, or training consistently. Add gamification: XP for finishing a workout, bonus XP for a new PR, bonus XP for hitting 3 workouts in a calendar week. Design the rates and level curve so early progress is fast (hook) but the system stays a meaningful long-term goal, not solved in a few months.

## Requirements

- XP starts fresh at zero for everyone at launch — no backfill of past history.
- Award XP at the `finishWorkout` choke point (`SwoleData/Sources/SwoleData/WorkoutSessionService.swift`) — the path every *live* workout goes through. (`ManualWorkoutEntryView` also creates already-finished `WorkoutSession`s directly, bypassing `finishWorkout` entirely; see Out of scope.)
- A workout can award a PR bonus per exercise that hit a new PR in that session (not capped at one).
- A PR only counts if the exercise has at least one prior *finished* session — the first-ever log of an exercise is a baseline, not a PR.
- The "3 workouts this week" bonus fires exactly once per calendar week, on the session that brings the week's finished-workout count to 3 (not on the 4th, 5th, ...).
- Level is derived from `totalXP`, never stored directly — can't drift out of sync.
- Leveling is uncapped/indefinite: no max level, and no level should take an ever-growing amount of time forever (avoid a curve that makes late levels take years).
- UI: level + XP progress bar on `TodayView`, no separate history screen or award animations for v1.

## Design

### Data model

New singleton model, alongside `UserSettings` in the schema:

```swift
// SwoleData/Sources/SwoleData/GamificationState.swift
import SwiftData

@Model
public final class GamificationState {
    public var totalXP: Int

    public init(totalXP: Int = 0) {
        self.totalXP = totalXP
    }
}
```

Add `GamificationState.self` to `swoleSchema` in `Schema.swift`. Seeded alongside `UserSettings` (in `StandardSeed.swift`, same place `UserSettings` is first created) — but `StandardSeed.seed` early-returns on any store that already has exercises, so this only creates the row on a brand-new install. Every existing install (any store seeded before this feature shipped) would never get the row through seeding alone. `awardXP` must not assume the row exists — it must create it lazily (check-then-insert) the first time a workout finishes on such a store, so the feature activates itself on upgrade rather than silently never running.

### XPCalculator (pure, testable — mirrors StatsCalculator style)

```swift
// SwoleData/Sources/SwoleData/XPCalculator.swift
public enum XPCalculator {
    public static let workoutXP = 60
    public static let prBonusXP = 20
    public static let weeklyBonusXP = 120

    private static let levelCurveConstant = 50.0
    private static let levelCurveExponent = 1.5
    private static let levelCurveCap = 2500

    /// XP required to go from `level` to `level + 1`.
    public static func xpForLevel(_ level: Int) -> Int {
        min(Int((levelCurveConstant * pow(Double(level), levelCurveExponent)).rounded()), levelCurveCap)
    }

    /// Current level for a total XP amount (level 1 = 0 XP).
    public static func level(forXP xp: Int) -> Int {
        var level = 1
        var remaining = xp
        while remaining >= xpForLevel(level) {
            remaining -= xpForLevel(level)
            level += 1
        }
        return level
    }

    /// (XP earned within current level, XP needed for current level, current level)
    public static func progress(forXP xp: Int) -> (current: Int, needed: Int, level: Int) {
        var level = 1
        var remaining = xp
        while remaining >= xpForLevel(level) {
            remaining -= xpForLevel(level)
            level += 1
        }
        return (remaining, xpForLevel(level), level)
    }
}
```

Curve: `need(L) = min(round(50 * L^1.5), 2500)`. Grows through ~level 13 (level 10 ≈ 7132 cumulative XP, level 13 ≈ 13379), then flattens to a flat 2500 XP/level forever — indefinite leveling without late-game levels taking years. At maintenance pace (~300 XP/week from base + weekly bonus alone, no PRs) that's roughly a level every 8 weeks once capped, forever.

### Award logic in finishWorkout

```swift
// WorkoutSessionService.swift
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
    let state: GamificationState
    if let existing = try context.fetch(FetchDescriptor<GamificationState>()).first {
        state = existing
    } else {
        state = GamificationState(totalXP: 0)
        context.insert(state)
    }

    var xp = XPCalculator.workoutXP

    let prCount = try newPRCount(for: session, in: context)
    xp += prCount * XPCalculator.prBonusXP

    if try isThirdWorkoutThisWeek(session, in: context) {
        xp += XPCalculator.weeklyBonusXP
    }

    state.totalXP += xp
}
```

`newPRCount` — for each exercise in `session.exerciseLogs`, compare this session's best set (weight × reps, same comparison `StatsCalculator.personalRecords` already uses) against prior *finished* sessions for that exercise; count it only if the exercise has ≥1 prior finished session and this session's best beats all of them. Reuses the existing best-set comparison logic from `StatsCalculator` rather than duplicating it — factor the per-exercise "is this a new best" check out of `StatsCalculator.personalRecords` into a small shared helper both call, if it isn't already isolated.

`isThirdWorkoutThisWeek` — count finished sessions (excluding this one being finished) whose `startedAt` falls in `Calendar.current.dateInterval(of: .weekOfYear, for: session.startedAt)`, same week-bucketing `StatsCalculator.streaks` already uses. Returns true iff that count `== 2` (this session becomes the 3rd).

### UI

`TodayView` adds a `@Query private var gamificationState: [GamificationState]` and a small level/progress bar row under the header (near `WeekStrip`), showing "Level N" and a progress bar for `progress(forXP:).current / .needed`. Presentation-only — no new interaction.

## Files touched

- `SwoleData/Sources/SwoleData/GamificationState.swift` — new model.
- `SwoleData/Sources/SwoleData/XPCalculator.swift` — new pure calculator.
- `SwoleData/Sources/SwoleData/Schema.swift` — register `GamificationState`.
- `SwoleData/Sources/SwoleData/StandardSeed.swift` — seed `GamificationState` alongside `UserSettings`.
- `SwoleData/Sources/SwoleData/WorkoutSessionService.swift` — award XP in `finishWorkout`.
- `SwoleData/Sources/SwoleData/StatsCalculator.swift` — extract shared "is new PR" helper if not already isolated from `personalRecords`.
- `5x5ive/5x5ive/TodayView.swift` — level/XP bar UI.

## Testing

- `XPCalculator`: `xpForLevel` boundary values, cap behavior (level well past 13 still returns 2500), `level(forXP:)` and `progress(forXP:)` at exact level-boundary XP values and mid-level values.
- `WorkoutSessionServiceTests` (extend existing finish-workout coverage): finishing a workout with no PRs and not the 3rd of the week awards exactly `workoutXP`; a session with 2 PR exercises awards `workoutXP + 2 * prBonusXP`; the very first finished session for a brand-new exercise awards no PR bonus; the 3rd finished session in a calendar week awards the weekly bonus, the 4th does not.
- `WorkoutSessionServiceTests`: `finishWorkout` creates `GamificationState` on the fly and still awards XP if the row is missing (covers the upgrade path on a pre-existing store); finishing several workouts in a row and reading `GamificationState.totalXP` through `XPCalculator.progress(forXP:)` produces the expected level/current/needed tuple end to end.
- Manual: finish workouts in the simulator, confirm the TodayView level/XP bar updates and matches expected math — run this against a store that already has workout history (not just a fresh seed), since that's the path the missing-row fix targets.

## Out of scope

- Backfilling XP for existing workout history.
- History/detail screen for past XP awards, toast/animation on level-up.
- Titles or cosmetic rewards per level — just the number and progress bar for v1.
- Reconciling manually-entered workouts (`ManualWorkoutEntryView`) with the weekly bonus: those sessions are created already-finished, bypass `finishWorkout` entirely, and so never award XP themselves — but they still count toward `isThirdWorkoutThisWeek`'s tally of finished sessions in the week (it counts all finished sessions, not just XP-awarding ones). A week mixing manual and live entries can therefore make the weekly bonus fire earlier than the 3rd *live* workout, or — if manual entries alone push the week's count past 3 before any live workout finishes — never fire that week at all, since the check requires the count to be exactly 2 at award time. Known limitation, not fixed here.
