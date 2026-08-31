# Active workout summary + rest-timer notifications — design

**Status:** approved (autonomous session, no human review requested for this task)
**Author:** Claude, 2026-08-31

## Problem

Today's screen (`TodayView`, the app's home tab) shows nothing about an
in-progress workout — the only way to see it is the full-screen
`ActiveWorkoutView` cover, and there's no way to back out of that cover
without cancelling or finishing. Two things are missing:

1. A small "mini player" summary of the active workout (and its rest
   timer, if one is running) visible from the home screen.
2. A notification when a rest timer finishes while the app isn't in
   the foreground — today, rest state lives only in the ephemeral
   `ActiveWorkoutViewModel` and produces no signal at all if you're not
   looking at the screen.

## Scope decisions

- "Push notifications" in the ask is, mechanically, **local
  notifications** (`UNUserNotificationCenter` + a time-interval
  trigger). Nothing server-side is involved — the rest end time is
  already known on-device the moment rest starts. No APNs, no
  entitlement beyond user notification authorization.
- The mini summary is shown from `RootView`, so it persists across all
  four tabs (not just Today) the way a mini-player does — this matches
  the existing pattern where `ActiveWorkoutView` itself is presented
  from `RootView`, not from `TodayView`. It still satisfies "home
  screen" since Today is the app's home tab and the bar is visible
  there.
- Rest-timer state must survive the `ActiveWorkoutView` being torn
  down (dismissed to show the mini bar) and must be readable from
  `RootView`, which does not own an `ActiveWorkoutViewModel`. So rest
  state is persisted onto `WorkoutSession` (SwiftData) rather than
  living only in the view model. The view model keeps its existing
  pure, tested `ActiveRest` computation; a thin sync layer in
  `ActiveWorkoutView` mirrors it onto the session.

## Components

### 1. `WorkoutSession` (SwoleData) — persisted rest fields

Add three optional attributes:
- `restStartDate: Date?`
- `restEndDate: Date?`
- `restLabel: String?`

All three are set together (rest starts) and cleared together (rest
skipped, or superseded by a new rest window). This is additive/optional
so it's a lightweight SwiftData migration.

### 2. `ActiveWorkoutViewModel` (SwoleData) — restore hook

Add `public func restore(startDate: Date, endDate: Date, label: String)`
that sets `activeRest` directly (no rest-outcome tracking needed for
restore — outcome only drives which rest duration to use when a rest
*starts*, and restore just reconstructs the still-running countdown as
`.success` — outcome isn't read anywhere off restored state, only
`remaining(at:)`/`progress(at:)`/`nextUpLabel`, which is verified in the
existing test suite structure).

No other behavior change to the view model — `startRest`/`skipRest`
still work exactly as before; persistence is bolted on from the view.

### 3. `RestNotificationPlanner` (SwoleData) — pure scheduling decision

```swift
public enum RestNotificationPlanner {
    /// nil if the rest has already elapsed (nothing to schedule).
    public static func secondsUntilFire(restEndDate: Date, now: Date) -> TimeInterval?
}
```

Pure, unit-tested. Keeps the "is this rest still in the future"
arithmetic out of the notification-wrapping code so it's testable
without `UNUserNotificationCenter`.

### 4. `NotificationManager` (5x5ive app target)

Mirrors the existing `HealthKitManager` pattern: a `@MainActor final
class` singleton wrapping a system framework, authorization requested
lazily the first time it's needed, every failure swallowed (a missed
rest notification is not a crash-worthy event).

```swift
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    func scheduleRestComplete(restEndDate: Date, body: String) async
    func cancelRestComplete()
}
```

Uses a fixed request identifier (`"rest-timer-complete"`) so
re-scheduling naturally replaces any pending request, and cancel is a
single `removePendingNotificationRequests`/`removeDeliveredNotifications`
call.

### 5. `ActiveWorkoutView` — minimize + persistence sync

- New small chevron-down button in the header (`accessibilityIdentifier
  "minimizeWorkoutButton"`) that calls `dismiss()` — same mechanism
  `WorkoutSummaryView`'s `onDone` already uses to close the
  item-bound `fullScreenCover` from `RootView`. Does not touch the
  session, so `RootView`'s active-session query still finds it.
- `.onAppear`: if `session.restEndDate` is set and still in the future,
  call `viewModel.restore(...)`; if it's set but already elapsed,
  clear all three fields on the session (stale state cleanup) and
  save.
- `.onChange(of: viewModel.activeRest)`: mirror the new value's
  `startDate`/`endDate`/`nextUpLabel` onto the session's three rest
  fields (or clear them on `nil`) and `try? modelContext.save()`.

### 6. `ActiveWorkoutBar` (new view, 5x5ive app target)

Compact card, styled consistent with `RestBar`/`Theme`: workout type +
elapsed time + `loggedSetCount/totalSetCount`, plus a live countdown
(via `TimelineView`, same math as `RestBar`) when
`session.restEndDate` is in the future. Whole card is a `Button` that
re-presents the session. Rendered in `RootView` between the tab
content and `CustomTabBar`, shown when there's an active session and
it isn't currently presented full-screen.

### 7. `RootView` — scene-phase driven scheduling

`@Environment(\.scenePhase)`, `.onChange(of: scenePhase)`:
- `→ .background`: if the active session has a future `restEndDate`,
  call `NotificationManager.shared.scheduleRestComplete`.
- `→ .active`: `NotificationManager.shared.cancelRestComplete()` —
  the user is back, no need for a notification that would otherwise
  still fire while they're already looking at the countdown.

No scheduling on ordinary minimize (dismiss without backgrounding) —
only an actual scene-phase transition to background triggers it, since
that's the only time the countdown isn't visible somewhere.

## Data flow (rest starts while foregrounded, then app backgrounds)

1. User logs a set → `ActiveWorkoutViewModel.startRest` sets
   `activeRest`.
2. `ActiveWorkoutView`'s `onChange` mirrors it onto
   `session.restStartDate/restEndDate/restLabel`, saves.
3. `RootView`'s bar (if the workout is minimized) or the in-cover
   `RestBar` (if not) shows the live countdown either way, reading
   from the same persisted values (bar) or the live view model
   (RestBar) — both derive from the same start/end.
4. App backgrounds → `RootView` schedules a local notification for
   `restEndDate` with the current `restLabel` as its body.
5. App returns to foreground → `RootView` cancels the pending
   notification. If the rest already elapsed while backgrounded,
   `ActiveWorkoutView.onAppear`'s stale-cleanup (or, if the bar/cover
   was never torn down, nothing — the countdown just reads 0 the same
   way it already does today) handles it.

## Testing

- SwoleData (`swift test`, `Testing` framework):
  - `ActiveWorkoutViewModelTests`: add a case for `restore(...)`
    setting `activeRest` such that `remaining(at:)` reflects the
    restored window.
  - New `RestNotificationPlannerTests`: future end date → seconds
    returned; past end date → `nil`; exact-now edge case.
- 5x5ive UI tests (`XCTest`, simulator):
  - Minimizing an active workout (during a running rest) shows the
    `ActiveWorkoutBar` on the Today tab with a countdown, and tapping
    it reopens `ActiveWorkoutView` with the same rest still running.
  - Cancelling/finishing a workout removes the bar.
- No unit coverage for `NotificationManager` itself (matches
  `HealthKitManager`, which is also untested — it's a thin, unmockable
  wrapper around a system framework; the decision logic it depends on
  is covered by `RestNotificationPlannerTests`).

## Out of scope

- Remote/APNs push (not needed — see Scope decisions).
- Live Activities / Dynamic Island (bigger feature, not asked for).
- WidgetKit home-screen (springboard) widget — "home screen" here
  means the app's Today tab per the Scope decisions above.
