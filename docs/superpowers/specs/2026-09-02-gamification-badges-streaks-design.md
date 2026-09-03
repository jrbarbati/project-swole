# Gamification: badges + streaks

## Problem

XP/leveling ([[2026-08-29-xp-leveling-design]]) gives a session-to-session reward loop but nothing that celebrates long-arc milestones — total weight moved on a lift, total workouts logged, sustained consistency. Add a badge system for those milestones, and redefine the existing "week streak" stat to require real consistency (3+ workouts/week) rather than crediting any single session.

## Requirements

- Per-exercise cumulative-volume badges: 1,000 / 5,000 / 10,000 / 25,000 / 50,000 / 100,000 lb lifted (lifetime, that exercise only). kg equivalent (round tiers, not a literal conversion): 500 / 2,500 / 5,000 / 10,000 / 25,000 / 50,000 kg. Applies to each of the app's exercises independently.
- Total-volume badges (summed across every exercise): 2,000 / 5,000 / 10,000 / 15,000 / 20,000 lb, then +10,000 lb indefinitely (30k, 40k, 50k, ...). kg: 1,000 / 2,500 / 5,000 / 7,500 / 10,000, then +5,000 indefinitely. Open-ended — no cap.
- Workout-count badges: 10 / 25 / 50 / 100 / 250 / 500 finished workouts. Unit-independent.
- Streak badges: 4 / 12 / 26 / 52 weeks. Built on a **redefined** streak: a week only counts toward a streak if it has 3+ finished workouts (was: any workout). This changes `StatsCalculator.streaks`'s existing "week streak" stat on `StatsView` too — one consistent definition app-wide, not a separate badge-only number.
- Badges are computed, not stored — no new `@Model`, no schema migration. Same pattern `StatsCalculator`/`XPCalculator` already use: pure functions over the existing `ModelContext`.
- A "new badge" reveal happens at the same moment XP reveals, on `finishWorkout` — mirrors how PR bonuses are detected today (compare state excluding vs. including the session being finished).
- Badges live on `StatsView` as a new section: grid of tiles (locked = dimmed + lock glyph, unlocked = full color), tap a tile for a detail sheet (title, unlocked date or progress toward the next tier).
- Unit-aware: which ladder (lb or kg) applies is `UserSettings.unit`, read the same way `StatsView` already does (`settingsList.first?.unit ?? .lb`).

## Design

### No new model — `BadgeCalculator` (pure, mirrors `StatsCalculator`)

```swift
// SwoleData/Sources/SwoleData/BadgeCalculator.swift
public enum BadgeCategory: Hashable, Sendable {
    case exerciseVolume(exerciseName: String)
    case totalVolume
    case workoutCount
    case streak
}

public struct Badge: Identifiable, Equatable, Sendable {
    public let id: String                  // stable across unit switches, e.g. "volume.Squat.2"
    public let category: BadgeCategory
    public let title: String               // "Squat — 10,000 lb Lifted"
    public let iconName: String            // SF Symbol
    public let isUnlocked: Bool
    public let unlockedAt: Date?
    public let progressCurrent: Double     // in the caller's unit
    public let progressTarget: Double      // in the caller's unit
}

public enum BadgeCalculator {
    public static func allBadges(unit: MeasurementUnit, in context: ModelContext, now: Date = .now) throws -> [Badge]

    /// Badges that flip from locked to unlocked specifically because of `session`
    /// (compares totals excluding vs. including it, same trick `WorkoutSessionService`
    /// already uses for PR detection).
    public static func newlyUnlocked(for session: WorkoutSession, unit: MeasurementUnit, in context: ModelContext) throws -> [Badge]
}
```

**Tier tables** — hardcoded per unit, not derived by literal lb→kg conversion (approved: clean round numbers per unit, not converted decimals):

| Category | lb | kg |
|---|---|---|
| Per-exercise volume | 1,000 / 5,000 / 10,000 / 25,000 / 50,000 / 100,000 | 500 / 2,500 / 5,000 / 10,000 / 25,000 / 50,000 |
| Total volume | 2,000 / 5,000 / 10,000 / 15,000 / 20,000, +10,000/tier after | 1,000 / 2,500 / 5,000 / 7,500 / 10,000, +5,000/tier after |
| Workout count | 10 / 25 / 50 / 100 / 250 / 500 (unit-independent) | same |
| Streak (weeks) | 4 / 12 / 26 / 52 (unit-independent) | same |

The total-volume ladder is open-ended (index-based generator: fixed 5-entry prefix, then `prefix.last + step * n`). `allBadges` returns every **earned** tier for that category plus exactly one locked tile for the next tier — never the full infinite ladder.

**Source aggregates**, each computed from finished sessions only (`finishedAt != nil`), each with an `excluding sessionID:` parameter so `newlyUnlocked` can compute "before" and "after" from the same code path (same shape as `StatsCalculator.priorSucceededMaxWeight` and `isThirdFinishedWorkoutThisWeek`):

- Per-exercise cumulative volume: `ExerciseLog.volume` summed per `Exercise`.
- Total cumulative volume: summed across all exercises.
- Workout count: count of finished sessions.
- Streak: **longest** streak ever reached (`StreakInfo.longestWeeks`, redefined below), not the current streak — a streak badge, once earned, must not un-earn itself when the current streak later breaks. `StatsCalculator`'s existing consecutive-week-run scan is extracted into an internal helper operating on a supplied session list, so both `StatsCalculator.streaks(in:)` and `BadgeCalculator` can call it (one excluding a session, one not) without duplicating the run-length logic.

**Unlock dates**: a single chronological pass over finished sessions (oldest first), tracking running per-exercise/total/count totals, records the session whose completion first crosses each tier. Streak-tier unlock dates come from the same weekly-run scan, keyed to the week that completed the longest qualifying run. Best-effort — ties resolve to whichever session the forward scan reaches first.

### `StatsCalculator.streaks` redefinition

Currently: a week "counts" if it has ≥1 finished session. Change to ≥3. Concretely, `weekStarts` changes from "every distinct week with a session" to "every week whose session count is ≥3" — the rest of the run-length/current-streak logic is unchanged. This is a one-line filter change but touches the existing `StatsView` "week streak" card's meaning, not just badges.

### `finishWorkout` integration

```swift
// WorkoutSessionService.swift
public struct XPAward: Equatable {
    // ...existing fields...
    public let newBadges: [Badge]
}
```

In `finishWorkout`, after `session.finishedAt = .now` (so the calculators see it as finished) and using the same `settings` already fetched for `lastCompletedWorkoutType`:

```swift
let unit = settings?.unit ?? .lb
let newBadges = try BadgeCalculator.newlyUnlocked(for: session, unit: unit, in: context)
```

Folded into the returned `XPAward`.

### UI

**`XPRevealView`**: a new "New Badges" row list beneath the existing XP bonus chips, same staggered spring-in animation pattern (own `visibleBadgeCount` counter, continuing the delay sequence after the XP chips finish). Each row: SF Symbol icon + badge title, no XP value. Hidden entirely when `award.newBadges` is empty — no layout change for an ordinary workout.

**`StatsView`**: new "Badges" card, added after `recordsCard`. Header shows "X / Y earned" (Y = the 40 fixed-tier badges + earned-so-far-plus-one for the open-ended total-volume category). Body is one `LazyVGrid` (4 columns) per category (Streaks, Workouts, Total Volume, then one per exercise), each with a `MetaLabel` sub-header. A tile: circular icon, full color + no overlay when unlocked, dimmed + `lock.fill` overlay when locked. Tapping a tile presents a `.sheet` with title, icon, and either the unlock date or a progress bar (`progressCurrent`/`progressTarget` in the user's unit, formatted like the existing volume stats).

## Files touched

- `SwoleData/Sources/SwoleData/BadgeCalculator.swift` — new.
- `SwoleData/Sources/SwoleData/StatsCalculator.swift` — redefine `streaks`' week-qualifying threshold to ≥3; extract the consecutive-run scan into a session-list-based helper shared with `BadgeCalculator`.
- `SwoleData/Sources/SwoleData/WorkoutSessionService.swift` — `XPAward.newBadges`, computed in `finishWorkout`.
- `5x5ive/5x5ive/XPRevealView.swift` — new-badges row list.
- `5x5ive/5x5ive/StatsView.swift` — Badges card, tile grid, detail sheet.

## Testing

- `BadgeCalculatorTests` (new): tier-boundary crossing for each category (just under / exactly at / just over a threshold); per-exercise badges are independent per exercise; total-volume open-ended ladder generates the right next tier arbitrarily far past the fixed prefix and never enumerates more than one locked tile; workout-count and streak tiers unlock at the right counts; `newlyUnlocked` returns a tier exactly once (the session that crosses it) and never again on subsequent finishes; unit switch changes which ladder (and thus which id/tiers) is evaluated without crashing on badges "earned" under the other unit.
- `StatsCalculatorTests` (update existing streak tests to 3-workout weeks; add a new test that a week with 1-2 workouts does **not** count toward the streak, and that `longestWeeks` still reflects a broken 3-per-week run correctly).
- `WorkoutSessionServiceTests` (extend): finishing a workout that crosses a per-exercise volume tier returns it in `newBadges`; finishing one that doesn't crosses nothing; a tier already earned before this session is not returned again.
- UI test (`_x5iveUITests`, new): finishing the first-ever workout (which trivially crosses the smallest per-exercise volume tier given realistic seeded weights) shows the "New Badges" row on the XP reveal screen.

## Out of scope

- Backfilling badge "earned" state or notifications for history that predates this feature beyond what the computed pass naturally picks up (it does pick up all prior history automatically — computed, not seeded — but there's no special first-launch "you already earned N badges" moment).
- Badge-linked XP or cosmetic rewards.
- Titles/tiers beyond the ladders above (e.g. no "platinum/gold" skinning).
- Reconciling `ManualWorkoutEntryView` sessions with the reveal moment: they're created already-finished and never go through `finishWorkout`, so they contribute to badge totals (finished-session queries pick them up) but never trigger a reveal screen for badges earned that way — same known gap XP has today.
