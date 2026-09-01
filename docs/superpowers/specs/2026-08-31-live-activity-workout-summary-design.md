# Live Activity workout summary — design

**Status:** approved by user, 2026-08-31
**Author:** Claude, 2026-08-31

## Problem

Today, an active workout is invisible outside the app: locking the screen
shows nothing, and the only signal you get while away is a single local
notification when a rest timer completes (see
`docs/superpowers/specs/2026-08-31-active-workout-summary-notifications-design.md`).
There's no persistent, glanceable summary of the in-progress workout on the
Lock Screen or in the Dynamic Island the way Apple's own apps (Timers,
Maps, Sports) provide via `ActivityKit` Live Activities.

## Scope decisions

- **Content:** current exercise name, sets completed/total *for that
  exercise* (e.g. "3/5"), the next exercise's name, and — when one is
  running — a live rest countdown. Not overall-workout set count; that's
  already covered by the in-app mini bar and isn't what a glanceable
  Lock Screen card is for.
- **No backend.** This app has no server. A killed app process cannot push
  remote updates to a Live Activity. Accepted behavior: every update sets a
  `staleDate` a short buffer past the next expected state change, so a
  killed app's Activity dims (`ActivityUIConfiguration`'s built-in stale
  presentation) and iOS eventually ends it on its own. No watchdog, no
  attempt to detect termination explicitly.
- **Rest countdown renders natively.** The Live Activity's countdown uses
  SwiftUI's `Text(timerInterval:countsDown:)` against the rest window's
  start/end dates, which ticks on-screen with zero ongoing work from the
  app — not the per-second `activity.update()` calls the in-app mini bar
  uses (that pattern exists there only because a plain `Text` inside a
  `TimelineView` needed it; ActivityKit's Lock Screen renderer gives us the
  native primitive instead).
- **Trigger location: the app-target UI layer, not `SwoleData`.**
  `WorkoutSessionService` (in `SwoleData`) is also the path for backfilled
  historical workouts (`ManualWorkoutEntryView` constructs an
  already-`finishedAt`-set `WorkoutSession` directly and never calls
  `WorkoutSessionService.startWorkout`, so this isn't actually a
  disambiguation hazard either way) — but `ActivityKit` is a UI/App
  framework, and `SwoleData`'s test suite runs via plain `swift test` with
  no simulator. Live Activity calls belong in the app target, at the same
  call sites that already drive `NotificationManager` and the mini bar's
  persisted-rest-state sync.
- **One Live Activity at a time**, matching the app's existing
  one-active-session invariant.

## Components

### 1. New Xcode target: a WidgetKit Extension

Unlike every prior change in this app, this one file-system-synchronized
groups can't absorb on their own — a WidgetKit Extension is a distinct
Xcode target (its own bundle ID suffix, its own `Info.plist`, linked
against `WidgetKit`/`SwiftUI`/`ActivityKit`, with `NSSupportsLiveActivities`
set in the *main app's* Info.plist). This is implementation-plan work, not
something this spec can fully pin down outside Xcode — the plan should
call out "create the target" as its own early step so a build failure
there doesn't get conflated with a code failure.

The new target links against the existing `SwoleData` Swift package (an
SPM package can be shared by multiple targets in one project) so both
processes — the main app and the widget extension — use one shared
attributes type without duplicating it.

### 2. `WorkoutActivityAttributes` (SwoleData, new file)

```swift
import ActivityKit

public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var currentExerciseName: String
        public var completedSets: Int
        public var totalSets: Int
        public var nextExerciseName: String?
        public var restStartDate: Date?
        public var restEndDate: Date?

        public init(currentExerciseName: String, completedSets: Int, totalSets: Int, nextExerciseName: String?, restStartDate: Date?, restEndDate: Date?) {
            self.currentExerciseName = currentExerciseName
            self.completedSets = completedSets
            self.totalSets = totalSets
            self.nextExerciseName = nextExerciseName
            self.restStartDate = restStartDate
            self.restEndDate = restEndDate
        }
    }

    public var workoutTypeRawValue: String

    public init(workoutTypeRawValue: String) {
        self.workoutTypeRawValue = workoutTypeRawValue
    }
}
```

Plain data, `Codable`/`Hashable` per `ActivityAttributes`' requirements —
no app-target or widget-extension-only dependency beyond the `ActivityKit`
import itself, which is available on every platform this project targets
(iOS 16.1+, far below this project's actual deployment target).

### 3. `LiveActivityManager` (app target, new file)

Mirrors the existing `NotificationManager`/`HealthKitManager` shape: a
`@MainActor final class` singleton, every failure swallowed (an
unavailable or denied Live Activity is not crash-worthy), holding at most
one `Activity<WorkoutActivityAttributes>` reference.

```swift
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<WorkoutActivityAttributes>?

    func start(workoutTypeRawValue: String, state: WorkoutActivityAttributes.ContentState)
    func update(state: WorkoutActivityAttributes.ContentState)
    func end()
    /// Called from RootView's active-session reconciliation: re-attaches to
    /// an already-running system Activity after an app relaunch, if one
    /// still exists (e.g. background→foreground, not a kill).
    func reconcile(hasActiveSession: Bool, currentState: WorkoutActivityAttributes.ContentState?)
}
```

`start`/`update` compute a `staleDate`: if `state.restEndDate` is set, a
short buffer (e.g. 2 minutes) past it; otherwise a shorter fixed buffer
(e.g. 90 seconds) past "now", re-armed on every update — so a live,
actively-updating workout never goes stale, while one whose app process
died stops getting re-armed and dims on schedule.

### 4. Widget extension UI (new target)

One `ActivityConfiguration<WorkoutActivityAttributes>` in a
`WidgetBundle`, rendering:
- **Lock Screen banner:** exercise name + "N/M sets", the rest countdown
  (`Text(timerInterval:countsDown:)`, shown only when `restEndDate` is
  set) if resting, and next-exercise name as secondary text.
- **Dynamic Island — compact:** exercise name (leading) + countdown or set
  progress (trailing), whichever is more useful at a glance while resting
  vs. not.
- **Dynamic Island — minimal:** a single glyph/short label (the Island can
  show multiple apps' minimal states at once, so this must stay terse).
- **Dynamic Island — expanded:** the full banner content, laid out across
  the expanded regions.

The extension imports only `WidgetKit`, `SwiftUI`, `ActivityKit`, and
`SwoleData` (for `WorkoutActivityAttributes`) — never the app target,
never SwiftData/`ModelContainer`. It is a pure renderer of whatever
`ContentState` it's handed; all data-fetching happens in the main app
process.

## Data flow / lifecycle

All trigger points live in the app target, alongside the existing
`NotificationManager`/mini-bar call sites:

- **Start** — `TodayView.startWorkout()`, immediately after
  `WorkoutSessionService.startWorkout` succeeds: build the initial
  `ContentState` from the first exercise log and call
  `LiveActivityManager.shared.start(...)`.
- **Resume-on-relaunch** — mirrors `ActiveWorkoutView`'s
  `restoreOrClearPersistedRest` pattern. `RootView`'s existing
  active-session reconciliation (`onAppear`, the
  `activeSessions.first?.persistentModelID` `onChange`) calls
  `LiveActivityManager.shared.reconcile(hasActiveSession:currentState:)`:
  if there's an active session but no matching system `Activity` (found
  via `Activity<WorkoutActivityAttributes>.activities`), start a fresh one
  from current state; if there's an `Activity` but no active session
  (shouldn't normally happen — belt-and-suspenders), end it.
- **Update** — `ActiveWorkoutView`'s existing state-sync points get a
  sibling call: `syncRestToSession` (rest start/end/skip) and the
  exercise-advance points (`onAppear`'s initial focus, and
  `onChange(of: viewModel.completion?.logID)`) each also call
  `LiveActivityManager.shared.update(state:)` with a freshly-built
  `ContentState`.
- **End** — `ActiveWorkoutView.finish()` and `.cancel()` call
  `LiveActivityManager.shared.end()` with `dismissalPolicy: .immediate`.

## Error handling & edge cases

- **Permission denied / Live Activities disabled in Settings:**
  `Activity.request` throws; swallowed exactly like every other
  `NotificationManager`-style failure. Nothing else in the app is
  affected — this is a pure add-on with no dependents.
- **One-at-a-time invariant:** `LiveActivityManager` holds a single
  `currentActivity` reference; `start` is only ever called from the one
  workout-start call site, and `reconcile` checks for an existing system
  Activity before starting another, so there's no duplicate-request race.
- **Widget extension has no data access of its own** — no
  `ModelContainer`, no SwiftData import. It only ever renders the
  `ContentState` it's handed. This keeps the extension process fully
  isolated from the main app's persistence layer, matching how every
  other WidgetKit extension in the ecosystem works.
- **Simulator limitation (manual-testing note, not a code concern):**
  Dynamic Island only renders on notched/Dynamic-Island simulator devices
  (iPhone 14 Pro and later); the Lock Screen banner renders on any
  simulator via the device's lock screen.

## Testing

- **SwoleData (`swift test`):** `WorkoutActivityAttributes.ContentState`
  is plain data — construction and `Equatable`/`Hashable` behavior get a
  straightforward unit test, no simulator needed.
- **`LiveActivityManager`:** no dedicated unit test, consistent with the
  existing `NotificationManager`/`HealthKitManager` precedent — it's a
  thin, unmockable wrapper around a system framework whose only
  interesting logic (the staleness math) is small enough to inline and
  review, not extract.
- **UI tests:** XCUITest cannot inspect Live Activity or Dynamic Island
  content — it renders in a separate system process outside the app's own
  accessibility tree. No new XCUITest coverage is added for the Live
  Activity's *content*; the existing minimize/mini-bar/notification tests
  are unaffected since this is a pure add-on. Manual verification is
  required instead: start a workout, lock the Lock Screen, confirm the
  banner; on an iPhone 14 Pro+ (or equivalent) simulator, confirm the
  Dynamic Island's compact/minimal/expanded states; background the app
  during a rest period and confirm the countdown keeps ticking with no
  app process running; force-quit the app mid-workout and confirm the
  Activity dims/ends around its staleness window.

## Out of scope

- Remote/push updates to the Live Activity (no server exists or is
  planned for this app).
- Interactive Live Activity buttons (e.g. a "skip rest" button on the
  Lock Screen) — `ActivityKit` supports this via App Intents, but it's a
  separate, larger feature or a natural follow-up, not part of this spec.
- Apple Watch complications/companion app — unrelated surface, not
  requested.
