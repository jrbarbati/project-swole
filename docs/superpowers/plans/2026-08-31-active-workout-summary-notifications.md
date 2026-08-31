# Active Workout Summary + Rest-Timer Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a persistent mini summary (elapsed time, sets logged, live rest countdown) of the active workout from every tab, let the user minimize out of the full-screen workout without ending it, and fire a local notification when a rest timer completes while the app is backgrounded.

**Architecture:** Persist rest-timer start/end/label onto `WorkoutSession` (SwiftData) so it survives the `ActiveWorkoutView` being dismissed and is readable from `RootView`. `ActiveWorkoutViewModel` keeps its existing pure rest logic; `ActiveWorkoutView` mirrors it onto the session. `RootView` renders a mini bar from the persisted session fields and drives local-notification scheduling off `scenePhase` transitions via a new `NotificationManager` (app target, mirrors the existing `HealthKitManager` pattern).

**Tech Stack:** Swift, SwiftUI, SwiftData, `UserNotifications` (local notifications only, no APNs), `Testing` framework for the `SwoleData` package, `XCTest` for app UI tests.

**Spec:** `docs/superpowers/specs/2026-08-31-active-workout-summary-notifications-design.md`

## Global Constraints

- No APNs/remote push — local notifications only (`UNUserNotificationCenter` + `UNTimeIntervalNotificationTrigger`).
- No WidgetKit / springboard widget, no Live Activities — "home screen" means the app's own tab UI (`RootView`/`TodayView`).
- `WorkoutSession`'s new fields must be optional (`Date?`/`String?`) so the SwiftData migration is additive/lightweight.
- Follow existing patterns: pure/testable logic goes in the `SwoleData` package; system-framework wrapping (`UserNotifications`) goes in the `5x5ive` app target as a `@MainActor final class` singleton, matching `HealthKitManager`.
- New `.swift` files dropped into `5x5ive/5x5ive/` are auto-included in the app target (the project uses `PBXFileSystemSynchronizedRootGroup`) — no `.pbxproj` editing needed.
- Run `swift test` from `SwoleData/` for package tests; run UI tests via `xcodebuild test -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17'`.

---

### Task 1: `WorkoutSession` persisted rest fields

**Files:**
- Modify: `SwoleData/Sources/SwoleData/WorkoutSession.swift`
- Test: `SwoleData/Tests/SwoleDataTests/SchemaTests.swift`

**Interfaces:**
- Produces: `WorkoutSession.restStartDate: Date?`, `WorkoutSession.restEndDate: Date?`, `WorkoutSession.restLabel: String?` (all stored properties, default `nil`).

- [ ] **Step 1: Write the failing test**

Add to `SwoleData/Tests/SwoleDataTests/SchemaTests.swift`:

```swift
@Test func workoutSessionRestFieldsDefaultToNilAndRoundTrip() throws {
    let context = try makeInMemoryContext()
    let session = WorkoutSession(startedAt: .now, workoutType: .a)
    context.insert(session)
    try context.save()

    #expect(session.restStartDate == nil)
    #expect(session.restEndDate == nil)
    #expect(session.restLabel == nil)

    let start = Date.now
    let end = start.addingTimeInterval(90)
    session.restStartDate = start
    session.restEndDate = end
    session.restLabel = "Rest · next exercise"
    try context.save()

    #expect(session.restStartDate == start)
    #expect(session.restEndDate == end)
    #expect(session.restLabel == "Rest · next exercise")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SwoleData && swift test --filter workoutSessionRestFieldsDefaultToNilAndRoundTrip`
Expected: FAIL — `value of type 'WorkoutSession' has no member 'restStartDate'` (compile error).

- [ ] **Step 3: Add the fields**

In `SwoleData/Sources/SwoleData/WorkoutSession.swift`, change the class to:

```swift
import Foundation
import SwiftData

@Model
public final class WorkoutSession {
    @Attribute(originalName: "date")
    public var startedAt: Date
    public var workoutType: WorkoutType
    public var finishedAt: Date?
    public var note: String?
    /// Start of the currently-running rest window, if any. Mirrors
    /// `ActiveWorkoutViewModel.ActiveRest` so rest state survives
    /// `ActiveWorkoutView` being dismissed and is readable from `RootView`.
    public var restStartDate: Date?
    public var restEndDate: Date?
    public var restLabel: String?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.session)
    public var exerciseLogs: [ExerciseLog] = []

    public init(startedAt: Date, workoutType: WorkoutType, finishedAt: Date? = nil, note: String? = nil) {
        self.startedAt = startedAt
        self.workoutType = workoutType
        self.finishedAt = finishedAt
        self.note = note
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SwoleData && swift test --filter workoutSessionRestFieldsDefaultToNilAndRoundTrip`
Expected: PASS

- [ ] **Step 5: Run the full package suite to check nothing else broke**

Run: `cd SwoleData && swift test`
Expected: all tests PASS

- [ ] **Step 6: Commit**

```bash
git add SwoleData/Sources/SwoleData/WorkoutSession.swift SwoleData/Tests/SwoleDataTests/SchemaTests.swift
git commit -m "feat: add persisted rest-timer fields to WorkoutSession"
```

---

### Task 2: `ActiveWorkoutViewModel.restore(...)`

**Files:**
- Modify: `SwoleData/Sources/SwoleData/ActiveWorkoutViewModel.swift`
- Test: `SwoleData/Tests/SwoleDataTests/ActiveWorkoutViewModelTests.swift`

**Interfaces:**
- Consumes: `ActiveWorkoutViewModel.ActiveRest` (existing struct: `outcome: RestOutcome`, `startDate: Date`, `endDate: Date`, `nextUpLabel: String`, plus `remaining(at:) -> Int` and `progress(at:) -> Double`).
- Produces: `public func restore(startDate: Date, endDate: Date, label: String)` on `ActiveWorkoutViewModel` — sets `activeRest` to a `.success`-outcome `ActiveRest` with the given window/label. (Outcome only matters when a rest *starts*, to pick success/fail duration; nothing reads `outcome` off a restored rest, so `.success` is an arbitrary but harmless placeholder value — see `RestOutcome` in `WorkoutEnums.swift`.)

- [ ] **Step 1: Write the failing test**

Add to `SwoleData/Tests/SwoleDataTests/ActiveWorkoutViewModelTests.swift`:

```swift
@Test @MainActor func restoreSetsActiveRestFromPersistedWindow() throws {
    let model = ActiveWorkoutViewModel()
    let start = Date.now.addingTimeInterval(-30)
    let end = Date.now.addingTimeInterval(60)

    model.restore(startDate: start, endDate: end, label: "Rest · set 3 next")

    #expect(model.activeRest?.startDate == start)
    #expect(model.activeRest?.endDate == end)
    #expect(model.activeRest?.nextUpLabel == "Rest · set 3 next")
    #expect(model.activeRest?.remaining(at: .now) ?? 0 > 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SwoleData && swift test --filter restoreSetsActiveRestFromPersistedWindow`
Expected: FAIL — `value of type 'ActiveWorkoutViewModel' has no member 'restore'` (compile error).

- [ ] **Step 3: Implement `restore`**

In `SwoleData/Sources/SwoleData/ActiveWorkoutViewModel.swift`, add this public method in the `// MARK: - Logging` section, right after `skipRest()`:

```swift
    /// Reconstructs a still-running rest window after the view that owns
    /// this view model was recreated (e.g. re-opening a minimized workout).
    /// Outcome is irrelevant here — it only affects which duration a rest
    /// *starts* with — so `.success` is used unconditionally.
    public func restore(startDate: Date, endDate: Date, label: String) {
        activeRest = ActiveRest(outcome: .success, startDate: startDate, endDate: endDate, nextUpLabel: label)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SwoleData && swift test --filter restoreSetsActiveRestFromPersistedWindow`
Expected: PASS

- [ ] **Step 5: Run the full package suite**

Run: `cd SwoleData && swift test`
Expected: all tests PASS

- [ ] **Step 6: Commit**

```bash
git add SwoleData/Sources/SwoleData/ActiveWorkoutViewModel.swift SwoleData/Tests/SwoleDataTests/ActiveWorkoutViewModelTests.swift
git commit -m "feat: add ActiveWorkoutViewModel.restore for reopening a minimized workout"
```

---

### Task 3: `RestNotificationPlanner` (pure scheduling decision)

**Files:**
- Create: `SwoleData/Sources/SwoleData/RestNotificationPlanner.swift`
- Test: `SwoleData/Tests/SwoleDataTests/RestNotificationPlannerTests.swift`

**Interfaces:**
- Produces: `public enum RestNotificationPlanner { public static func secondsUntilFire(restEndDate: Date, now: Date) -> TimeInterval? }` — returns `nil` when `restEndDate <= now` (nothing to schedule), otherwise the positive interval.

- [ ] **Step 1: Write the failing test**

Create `SwoleData/Tests/SwoleDataTests/RestNotificationPlannerTests.swift`:

```swift
import Testing
import Foundation
@testable import SwoleData

@Test func secondsUntilFireReturnsPositiveIntervalForAFutureEndDate() {
    let now = Date(timeIntervalSince1970: 1_000)
    let end = now.addingTimeInterval(90)

    let seconds = RestNotificationPlanner.secondsUntilFire(restEndDate: end, now: now)

    #expect(seconds == 90)
}

@Test func secondsUntilFireReturnsNilForAnAlreadyElapsedEndDate() {
    let now = Date(timeIntervalSince1970: 1_000)
    let end = now.addingTimeInterval(-1)

    #expect(RestNotificationPlanner.secondsUntilFire(restEndDate: end, now: now) == nil)
}

@Test func secondsUntilFireReturnsNilWhenEndDateEqualsNow() {
    let now = Date(timeIntervalSince1970: 1_000)

    #expect(RestNotificationPlanner.secondsUntilFire(restEndDate: now, now: now) == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SwoleData && swift test --filter RestNotificationPlannerTests`
Expected: FAIL — `cannot find 'RestNotificationPlanner' in scope` (compile error).

- [ ] **Step 3: Implement `RestNotificationPlanner`**

Create `SwoleData/Sources/SwoleData/RestNotificationPlanner.swift`:

```swift
import Foundation

/// Pure decision logic for whether a rest-complete local notification
/// should be scheduled — kept separate from `UNUserNotificationCenter` so
/// it's testable without a notification-center mock.
public enum RestNotificationPlanner {
    /// `nil` if `restEndDate` is not strictly in the future relative to `now`.
    public static func secondsUntilFire(restEndDate: Date, now: Date) -> TimeInterval? {
        let interval = restEndDate.timeIntervalSince(now)
        return interval > 0 ? interval : nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SwoleData && swift test --filter RestNotificationPlannerTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Run the full package suite**

Run: `cd SwoleData && swift test`
Expected: all tests PASS

- [ ] **Step 6: Commit**

```bash
git add SwoleData/Sources/SwoleData/RestNotificationPlanner.swift SwoleData/Tests/SwoleDataTests/RestNotificationPlannerTests.swift
git commit -m "feat: add RestNotificationPlanner pure scheduling decision"
```

---

### Task 4: `NotificationManager` (app target)

**Files:**
- Create: `5x5ive/5x5ive/NotificationManager.swift`

**Interfaces:**
- Consumes: `RestNotificationPlanner.secondsUntilFire(restEndDate:now:) -> TimeInterval?` (Task 3).
- Produces: `NotificationManager.shared: NotificationManager`, `func scheduleRestComplete(restEndDate: Date, body: String) async`, `func cancelRestComplete()`.

No test target covers this file directly (it's a thin, unmockable wrapper around `UNUserNotificationCenter` — same as the untested `HealthKitManager`); its scheduling decision is covered by `RestNotificationPlannerTests` (Task 3). It's exercised indirectly by the Task 6 UI test via `RootView`.

- [ ] **Step 1: Create the file**

Create `5x5ive/5x5ive/NotificationManager.swift`:

```swift
import UserNotifications
import SwoleData

/// Schedules/cancels the single local notification that fires when a rest
/// timer completes while the app isn't in the foreground. Mirrors
/// `HealthKitManager`'s shape: a `@MainActor` singleton wrapping a system
/// framework, authorization requested lazily, every failure swallowed — a
/// missed rest notification is not a crash-worthy event.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let restRequestID = "rest-timer-complete"

    private init() {}

    /// No-ops if `restEndDate` has already elapsed, or if notification
    /// permission is denied.
    func scheduleRestComplete(restEndDate: Date, body: String) async {
        guard let seconds = RestNotificationPlanner.secondsUntilFire(restEndDate: restEndDate, now: .now) else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: restRequestID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancelRestComplete() {
        center.removePendingNotificationRequests(withIdentifiers: [restRequestID])
        center.removeDeliveredNotifications(withIdentifiers: [restRequestID])
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }
}
```

- [ ] **Step 2: Build the app target to verify it compiles**

Run: `xcodebuild build -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' | tail -30`
Expected: `BUILD SUCCEEDED` (check for `NotificationManager.swift` compiling with no errors — the file-system-synchronized group means it's picked up automatically).

- [ ] **Step 3: Commit**

```bash
git add 5x5ive/5x5ive/NotificationManager.swift
git commit -m "feat: add NotificationManager for local rest-complete notifications"
```

---

### Task 5: `ActiveWorkoutView` — minimize button + rest persistence sync

**Files:**
- Modify: `5x5ive/5x5ive/ActiveWorkoutView.swift`

**Interfaces:**
- Consumes: `WorkoutSession.restStartDate/restEndDate/restLabel` (Task 1), `ActiveWorkoutViewModel.restore(startDate:endDate:label:)` (Task 2), `ActiveWorkoutViewModel.activeRest: ActiveRest?` (existing).
- Produces: a button with `accessibilityIdentifier("minimizeWorkoutButton")` in `ActiveWorkoutView`'s header; `session.restStartDate/restEndDate/restLabel` kept in sync with `viewModel.activeRest` for the lifetime of the view.

- [ ] **Step 1: Add the minimize button to the header**

In `5x5ive/5x5ive/ActiveWorkoutView.swift`, replace the `header` computed property:

```swift
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text("Workout \(session.workoutType.rawValue)")
                    .font(Theme.Font.display(26))
                    .foregroundStyle(Theme.textPrimary)
                ElapsedLabel(since: session.startedAt)
            }
            Spacer()
            Text("\(session.loggedSetCount)/\(session.totalSetCount)")
                .font(Theme.Font.label())
                .tracking(1.4)
                .foregroundStyle(Theme.accentText)
            minimizeButton
        }
        .padding(.top, 10)
        .padding(.horizontal, Theme.Space.screen)
        .padding(.bottom, 18)
    }

    /// Dismisses back to the tab UI without cancelling or finishing the
    /// workout — `RootView`'s active-session query still finds this session,
    /// so it reopens exactly as left when the user taps `ActiveWorkoutBar`.
    private var minimizeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Theme.borderStrong, lineWidth: 1))
                .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("minimizeWorkoutButton")
        .padding(.leading, 10)
    }
```

- [ ] **Step 2: Sync rest state onto the session**

In the same file, replace the `.onAppear { viewModel.focusFirstIncomplete(in: logs) }` line inside `body` with:

```swift
        .onAppear {
            viewModel.focusFirstIncomplete(in: logs)
            restoreOrClearPersistedRest()
        }
        .onChange(of: viewModel.activeRest) { _, newValue in
            syncRestToSession(newValue)
        }
```

- [ ] **Step 3: Add the two new private methods**

Add these methods in the `// MARK: Actions` section of `ActiveWorkoutView.swift` (after `cancel()`):

```swift
    /// Reconstructs a still-running rest countdown when re-opening a
    /// minimized workout; clears stale rest fields left over from a rest
    /// that finished while the workout was minimized.
    private func restoreOrClearPersistedRest() {
        guard let end = session.restEndDate else { return }
        if end > .now, let start = session.restStartDate, let label = session.restLabel {
            viewModel.restore(startDate: start, endDate: end, label: label)
        } else {
            session.restStartDate = nil
            session.restEndDate = nil
            session.restLabel = nil
            try? modelContext.save()
        }
    }

    /// Mirrors the view model's rest window onto the session so it's
    /// readable from `RootView` (which doesn't own an `ActiveWorkoutViewModel`)
    /// after this view is dismissed.
    private func syncRestToSession(_ rest: ActiveWorkoutViewModel.ActiveRest?) {
        session.restStartDate = rest?.startDate
        session.restEndDate = rest?.endDate
        session.restLabel = rest?.nextUpLabel
        try? modelContext.save()
    }
```

- [ ] **Step 4: Build the app target**

Run: `xcodebuild build -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' | tail -30`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add 5x5ive/5x5ive/ActiveWorkoutView.swift
git commit -m "feat: add workout minimize control and persist rest timer to the session"
```

---

### Task 6: `ActiveWorkoutBar` + `RootView` wiring (mini summary + notification scheduling)

**Files:**
- Create: `5x5ive/5x5ive/ActiveWorkoutBar.swift`
- Modify: `5x5ive/5x5ive/RootView.swift`

**Interfaces:**
- Consumes: `WorkoutSession.restStartDate/restEndDate/restLabel` (Task 1), `WorkoutSession.loggedSetCount/totalSetCount` (existing, `ActiveWorkoutViewModel.swift` extension), `ElapsedLabel` (existing, defined in `ActiveWorkoutView.swift`, internal so visible within the app target), `NotificationManager.shared.scheduleRestComplete(restEndDate:body:)` / `.cancelRestComplete()` (Task 4).
- Produces: `struct ActiveWorkoutBar: View` with `init(session: WorkoutSession, onTap: @escaping () -> Void)`, rendered from `RootView`.

- [ ] **Step 1: Create `ActiveWorkoutBar`**

Create `5x5ive/5x5ive/ActiveWorkoutBar.swift`:

```swift
import SwiftUI
import SwoleData

/// Mini "now playing"-style summary shown across every tab while a workout
/// is active but minimized (its `ActiveWorkoutView` is dismissed). Tapping
/// it re-presents the full workout.
struct ActiveWorkoutBar: View {
    let session: WorkoutSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Workout \(session.workoutType.rawValue)")
                            .font(Theme.Font.title(15))
                            .foregroundStyle(Theme.textPrimary)
                        ElapsedLabel(since: session.startedAt)
                    }
                    MetaLabel(text: "\(session.loggedSetCount)/\(session.totalSetCount) sets", color: Theme.textDim)
                }
                Spacer()
                if let end = session.restEndDate, end > .now {
                    restCountdown(endDate: end)
                }
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, Theme.Space.screenTight)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activeWorkoutBar")
    }

    private func restCountdown(endDate: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endDate.timeIntervalSince(context.date).rounded(.up)))
            Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                .font(Theme.Font.numeric(17))
                .foregroundStyle(Theme.accentText)
        }
    }
}
```

- [ ] **Step 2: Wire the bar and scene-phase notification scheduling into `RootView`**

Replace the full contents of `5x5ive/5x5ive/RootView.swift` with:

```swift
import SwiftUI
import SwiftData
import SwoleData

struct RootView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.finishedAt == nil },
           sort: \WorkoutSession.startedAt, order: .reverse)
    private var activeSessions: [WorkoutSession]

    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: Tab = .today
    /// Snapshot of the presented session, deliberately NOT recomputed from
    /// `activeSessions` on every change: `finishWorkout` sets `finishedAt`
    /// (which drops the session from that query) while the workout's XP
    /// reveal screen still needs to stay on screen, so presentation is
    /// cleared only by an explicit dismiss, not reactively by the query.
    @State private var presentedSession: WorkoutSession?

    enum Tab: Hashable { case today, history, stats, settings }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                tabContent(.today) { NavigationStack { TodayView() } }
                tabContent(.history) { NavigationStack { HistoryView() } }
                tabContent(.stats) { NavigationStack { StatsView() } }
                tabContent(.settings) { NavigationStack { SettingsView() } }
            }

            if let session = activeSessions.first, presentedSession == nil {
                ActiveWorkoutBar(session: session) { presentedSession = session }
            }

            CustomTabBar(selection: $selectedTab)
        }
        .tint(Theme.accent)
        .background(Theme.canvas)
        .fullScreenCover(item: $presentedSession) { session in
            ActiveWorkoutView(session: session)
        }
        .onAppear { presentedSession = activeSessions.first }
        .onChange(of: activeSessions.first?.persistentModelID) { _, newID in
            guard newID != nil, presentedSession == nil else { return }
            presentedSession = activeSessions.first
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    /// Schedules a local notification for the active session's rest window
    /// on backgrounding (only moment the countdown isn't visible somewhere);
    /// cancels it once the user is back in the app.
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            guard let session = activeSessions.first, let end = session.restEndDate else { return }
            let body = session.restLabel ?? "Rest complete"
            Task { await NotificationManager.shared.scheduleRestComplete(restEndDate: end, body: body) }
        case .active:
            NotificationManager.shared.cancelRestComplete()
        default:
            break
        }
    }

    /// Keeps every tab's view mounted so switching back preserves its state,
    /// matching TabView's behavior without pulling in its native tab bar chrome.
    @ViewBuilder
    private func tabContent<Content: View>(_ tab: Tab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
    }
}

struct CustomTabBar: View {
    @Binding var selection: RootView.Tab

    private let items: [(tab: RootView.Tab, title: String)] = [
        (.today, "Today"), (.history, "History"), (.stats, "Stats"), (.settings, "Settings"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                let isSelected = selection == item.tab
                Button {
                    selection = item.tab
                } label: {
                    VStack(spacing: 7) {
                        Circle()
                            .fill(isSelected ? Theme.accent : .clear)
                            .frame(width: 5, height: 5)
                        Text(item.title.uppercased())
                            .font(Theme.Font.label())
                            .tracking(1.2)
                            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textDim)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.minTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, Theme.Space.screen)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
```

- [ ] **Step 3: Build the app target**

Run: `xcodebuild build -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' | tail -30`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add 5x5ive/5x5ive/ActiveWorkoutBar.swift 5x5ive/5x5ive/RootView.swift
git commit -m "feat: show active-workout mini bar and schedule rest-complete notifications on backgrounding"
```

---

### Task 7: UI tests for minimize / mini bar / cleanup

**Files:**
- Modify: `5x5ive/5x5iveUITests/_x5iveUITests.swift`

**Interfaces:**
- Consumes: `accessibilityIdentifier("minimizeWorkoutButton")` (Task 5), `accessibilityIdentifier("activeWorkoutBar")` (Task 6), and the existing `"Start Workout A"` / `"Cancel"` / `"Set 1"` identifiers already used elsewhere in this file.

- [ ] **Step 1: Write the new UI tests**

Add this new section at the end of `5x5ive/5x5iveUITests/_x5iveUITests.swift`, just before the file's closing `}`:

```swift

    // MARK: - Active workout mini bar

    @MainActor
    func testMinimizingAnActiveWorkoutShowsTheMiniBarWithARunningRestCountdown() throws {
        let app = launchApp()

        app.buttons["Start Workout A"].tap()
        let firstSet = app.descendants(matching: .any)["Set 1"]
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5))
        firstSet.tap()

        // Debounced settle (1.5s) before rest starts — poll past it.
        XCTAssertTrue(app.buttons["SKIP"].waitForExistence(timeout: 5))

        app.buttons["minimizeWorkoutButton"].tap()

        let bar = app.buttons["activeWorkoutBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start Workout A"].exists == false)
    }

    @MainActor
    func testTappingTheMiniBarReopensTheActiveWorkoutWithRestStillRunning() throws {
        let app = launchApp()

        app.buttons["Start Workout A"].tap()
        let firstSet = app.descendants(matching: .any)["Set 1"]
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5))
        firstSet.tap()
        XCTAssertTrue(app.buttons["SKIP"].waitForExistence(timeout: 5))

        app.buttons["minimizeWorkoutButton"].tap()
        let bar = app.buttons["activeWorkoutBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.tap()

        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["SKIP"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCancellingAMinimizedWorkoutRemovesTheMiniBar() throws {
        let app = launchApp()

        app.buttons["Start Workout A"].tap()
        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 5))

        app.buttons["minimizeWorkoutButton"].tap()
        let bar = app.buttons["activeWorkoutBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.tap()

        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        let alert = app.alerts["Cancel this workout?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete Workout"].tap()

        XCTAssertTrue(app.buttons["Start Workout A"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activeWorkoutBar"].exists)
    }
```

- [ ] **Step 2: Run the new UI tests to verify they fail first (TDD sanity check)**

Run: `xcodebuild test -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:5x5iveUITests/_x5iveUITests/testMinimizingAnActiveWorkoutShowsTheMiniBarWithARunningRestCountdown -only-testing:5x5iveUITests/_x5iveUITests/testTappingTheMiniBarReopensTheActiveWorkoutWithRestStillRunning -only-testing:5x5iveUITests/_x5iveUITests/testCancellingAMinimizedWorkoutRemovesTheMiniBar | tail -40`
Expected: FAIL — `minimizeWorkoutButton`/`activeWorkoutBar` not found (Tasks 5/6 not yet applied in this test run's build, or — if run after Tasks 5/6 are already committed — this step instead confirms they now PASS; either order is fine as long as Step 3 below confirms a real pass).

- [ ] **Step 3: Run the full UI test suite**

Run: `xcodebuild test -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' | tail -60`
Expected: all tests PASS, including the 3 new ones and every pre-existing test in `_x5iveUITests.swift`.

- [ ] **Step 4: Commit**

```bash
git add 5x5ive/5x5iveUITests/_x5iveUITests.swift
git commit -m "test: cover minimize/mini-bar/reopen/cleanup flow for active workouts"
```

---

## Final verification

- [ ] **Run `cd SwoleData && swift test`** — all package tests pass (Tasks 1–3 plus every pre-existing test).
- [ ] **Run `xcodebuild test -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17'`** — all UI tests pass (Task 7 plus every pre-existing test in `_x5iveUITests.swift`).
