# Live Activity Workout Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a Live Activity (Lock Screen banner + Dynamic Island) for the active workout — current exercise, its set progress, the next exercise, and a native-ticking rest countdown when one is running.

**Architecture:** A new WidgetKit Extension Xcode target renders an `ActivityConfiguration<WorkoutActivityAttributes>`. The attributes/content-state type is a small file added to both the app target and the widget extension target directly (not a `SwoleData` dependency — `ActivityKit` doesn't exist on macOS, and `SwoleData` is tested via plain `swift test` on macOS). A new `LiveActivityManager` (app target, mirrors the existing `NotificationManager`/`HealthKitManager` singleton pattern) owns the one `Activity` this app ever has at a time; it's driven from `ActiveWorkoutView`'s existing state-sync points.

**Tech Stack:** Swift, SwiftUI, WidgetKit, ActivityKit. Target creation is scripted with the `xcodeproj` Ruby gem (`gem install xcodeproj --user-install`) rather than hand-edited `.pbxproj` text, since a new Xcode target has many interdependent pbxproj sections that are far safer to generate through the gem's object model than to splice by hand.

**Spec:** `docs/superpowers/specs/2026-08-31-live-activity-workout-summary-design.md`

## Global Constraints

- `ActivityKit`/`WorkoutActivityAttributes` must NEVER be imported from anything inside `SwoleData/Sources/SwoleData/` — `SwoleData`'s `Package.swift` declares `.macOS(.v14)` (needed for `swift test` to run locally) and `ActivityKit` does not exist on macOS. This would break the whole package's test suite.
- The widget extension target must never link the app target, `SwoleData`, or SwiftData — it is a pure renderer of whatever `ContentState` it's handed. All data access happens in the main app process.
- Rest countdown in the Live Activity uses `Text(timerInterval:countsDown:)` against stored start/end dates — never an app-driven per-second update.
- One `Activity` at a time, matching the app's existing one-active-session invariant.
- No remote/push updates — this app has no server. Staleness is handled via `staleDate`, not a watchdog.
- Bundle ID for the widget extension: `com.fivebyfive.-x5ive.5x5iveWidget` (must be the app's own bundle ID, `com.fivebyfive.-x5ive`, plus a suffix — required by iOS for extension bundles).
- Deployment target for the new widget extension target: `26.5` (matches the app target's `IPHONEOS_DEPLOYMENT_TARGET`, already confirmed via `grep IPHONEOS_DEPLOYMENT_TARGET 5x5ive/5x5ive.xcodeproj/project.pbxproj`).
- The `5x5iveTests` target already uses Swift's `Testing` framework (`import Testing`, `@Test`, `#expect`) — confirmed via `5x5ive/5x5iveTests/_x5iveTests.swift`, not XCTest. New unit tests in that target must match.
- Build verification command throughout: `xcodebuild build -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'` (Pro Max is required for later Dynamic Island manual verification — pick a device with Dynamic Island support from `xcrun simctl list devices` if that exact name isn't available).

---

### Task 1: Create the WidgetKit Extension target (placeholder widget)

**Files:**
- Modify: `5x5ive/5x5ive.xcodeproj/project.pbxproj` (via script, not hand-edited)
- Create: `5x5ive/5x5iveWidget/FiveByFiveWidgetBundle.swift`

**Interfaces:**
- Produces: a new Xcode target named `5x5iveWidget` (product type `com.apple.product-type.app-extension`), embedded into the `5x5ive` app target's build product, with its own non-synchronized group at `5x5ive/5x5iveWidget/` (new files added to this folder later need an explicit pbxproj edit — this folder does NOT auto-pick-up new files the way `5x5ive/5x5ive/` does).
- Produces: `INFOPLIST_KEY_NSSupportsLiveActivities = YES` added to the app target's build settings (both Debug and Release).

This is the highest-risk task in this plan — it's the first WidgetKit extension ever added to this project, and there's no existing target in this repo to mirror. If the script fails with an error you can't resolve from the messages below, or if the build fails in a way that isn't a straightforward typo, report BLOCKED with the full error rather than improvising further pbxproj edits by hand.

- [ ] **Step 1: Install the `xcodeproj` gem**

Run: `gem install xcodeproj --user-install`
Expected: either `1 gem installed` (or similar) or a message that it's already installed. If this fails with a permissions error, do NOT use `sudo` — report BLOCKED with the exact error instead.

- [ ] **Step 2: Create the widget's source folder and placeholder file**

Create `5x5ive/5x5iveWidget/FiveByFiveWidgetBundle.swift`:

```swift
import WidgetKit
import SwiftUI

@main
struct FiveByFiveWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

/// Proves the extension target builds, embeds, and registers its
/// extension point correctly, before Task 4 adds the real
/// ActivityConfiguration content.
struct PlaceholderWidget: Widget {
    let kind: String = "PlaceholderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlaceholderProvider()) { _ in
            Text("5x5ive")
        }
        .configurationDisplayName("5x5ive")
        .description("Placeholder — replaced by the workout Live Activity.")
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}
```

- [ ] **Step 3: Write and run the target-creation script**

Create a scratch file `/tmp/add_widget_target.rb` (do not commit this file — it's a one-time setup script, not part of the app):

```ruby
require 'xcodeproj'

project_path = '5x5ive/5x5ive.xcodeproj'
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == '5x5ive' }
raise 'app target "5x5ive" not found' unless app_target

raise 'a target named 5x5iveWidget already exists — do not run this script twice' \
  if project.targets.any? { |t| t.name == '5x5iveWidget' }

widget_target = project.new_target(:app_extension, '5x5iveWidget', :ios, '26.5', nil, :swift)

widget_target.build_configurations.each do |config|
  config.build_settings.merge!(
    'CODE_SIGN_STYLE' => 'Automatic',
    'CURRENT_PROJECT_VERSION' => '1',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'INFOPLIST_KEY_CFBundleDisplayName' => '5x5iveWidget',
    'INFOPLIST_KEY_NSExtensionPointIdentifier' => 'com.apple.widgetkit-extension',
    'INFOPLIST_KEY_NSHumanReadableCopyright' => '',
    'IPHONEOS_DEPLOYMENT_TARGET' => '26.5',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
    'MARKETING_VERSION' => '1.0',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.fivebyfive.-x5ive.5x5iveWidget',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'SKIP_INSTALL' => 'YES',
    'SWIFT_EMIT_LOC_STRINGS' => 'YES',
    'SWIFT_VERSION' => '5.0',
    'TARGETED_DEVICE_FAMILY' => '1,2'
  )
end

widget_group = project.main_group.new_group('5x5iveWidget', '5x5iveWidget')
bundle_file_ref = widget_group.new_file('FiveByFiveWidgetBundle.swift')
widget_target.add_file_references([bundle_file_ref])

app_target.add_dependency(widget_target)

embed_phase = app_target.new_copy_files_build_phase('Embed Foundation Extensions')
embed_phase.symbol_dst_subfolder_spec = :plug_ins
embed_build_file = embed_phase.add_file_reference(widget_target.product_reference)
embed_build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

app_target.build_configurations.each do |config|
  config.build_settings['INFOPLIST_KEY_NSSupportsLiveActivities'] = 'YES'
end

project.save

puts "Done. Targets now: #{project.targets.map(&:name).join(', ')}"
```

Run: `ruby /tmp/add_widget_target.rb` (from the repo root, i.e. `/Users/josephbarbati/dev/project-swole` or your worktree's root)

Expected output: `Done. Targets now: 5x5ive, 5x5iveTests, 5x5iveUITests, 5x5iveWidget` (order may vary).

If `ruby` raises a `NoMethodError` or `ArgumentError` pointing at a specific xcodeproj API call, first try `ruby -rxcodeproj -e "puts Xcodeproj::Project.instance_method(:new_target).parameters.inspect"` (or the equivalent for whichever method failed) to see its real parameter list on the installed gem version, and adjust the call to match. If you can't get it to resolve after one or two targeted attempts, report BLOCKED with the exact error and what you tried.

- [ ] **Step 4: Verify the new target is visible to Xcode**

Run: `xcodebuild -list -project 5x5ive/5x5ive.xcodeproj`
Expected: the `Targets:` list includes `5x5iveWidget` alongside the three existing targets.

- [ ] **Step 5: Build the app target and verify the extension embeds**

Run: `xcodebuild build -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' 2>&1 | tail -40`
Expected: `** BUILD SUCCEEDED **`, with build log lines showing `5x5iveWidget.appex` being built and a `CopyPlistFile`/`CpResource`-style step embedding it under `PlugIns` inside `5x5ive.app`.

Then confirm the embedded extension physically exists and its extension point is correctly registered:

```bash
APP_PATH=$(xcodebuild -showBuildSettings -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' 2>/dev/null | grep -m1 'CODESIGNING_FOLDER_PATH' | awk '{print $3}')
find "$APP_PATH/PlugIns" -maxdepth 1
plutil -p "$APP_PATH/PlugIns/5x5iveWidget.appex/Info.plist" | grep -A2 NSExtension
```

Expected: `$APP_PATH/PlugIns` contains `5x5iveWidget.appex`, and the `plutil` output shows `NSExtensionPointIdentifier => "com.apple.widgetkit-extension"`.

- [ ] **Step 6: Commit**

```bash
git add 5x5ive/5x5ive.xcodeproj/project.pbxproj 5x5ive/5x5iveWidget/FiveByFiveWidgetBundle.swift
git commit -m "feat: add 5x5iveWidget extension target with placeholder widget"
```

Then delete the scratch script: `rm /tmp/add_widget_target.rb` (it's not part of the repo and should not be committed).

---

### Task 2: Shared `WorkoutActivityAttributes` type + unit test

**Files:**
- Create: `5x5ive/5x5iveWidget/WorkoutActivityAttributes.swift`
- Test: `5x5ive/5x5iveTests/WorkoutActivityAttributesTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `WorkoutActivityAttributes: ActivityAttributes` with nested `ContentState: Codable, Hashable` (fields: `currentExerciseName: String`, `completedSets: Int`, `totalSets: Int`, `nextExerciseName: String?`, `restStartDate: Date?`, `restEndDate: Date?`) and `workoutTypeRawValue: String` on the attributes itself. This type must be visible from BOTH the `5x5ive` app target and the `5x5iveWidget` extension target — Task 3 (app target) and Task 4 (widget target) both depend on it existing in both places.

This file physically lives in the widget's own folder (`5x5ive/5x5iveWidget/`, alongside `FiveByFiveWidgetBundle.swift` from Task 1) rather than the app's `5x5ive/5x5ive/` folder — that folder is a "file-system-synchronized" group for the widget target, so a new file dropped there is NOT automatically picked up by the APP target the way files in `5x5ive/5x5ive/` are. This task adds it explicitly to both targets' Sources build phases via the same `xcodeproj` scripting approach as Task 1.

- [ ] **Step 1: Create the shared attributes file**

Create `5x5ive/5x5iveWidget/WorkoutActivityAttributes.swift`:

```swift
import ActivityKit
import Foundation

/// Shared between the app target and the `5x5iveWidget` extension target
/// (added to both targets' Sources build phases — see the widget
/// extension task's setup script). Deliberately NOT part of the SwoleData
/// package: ActivityKit doesn't exist on macOS, and SwoleData's
/// Package.swift declares macOS(.v14) support for local `swift test`.
public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var currentExerciseName: String
        public var completedSets: Int
        public var totalSets: Int
        public var nextExerciseName: String?
        public var restStartDate: Date?
        public var restEndDate: Date?

        public init(
            currentExerciseName: String,
            completedSets: Int,
            totalSets: Int,
            nextExerciseName: String?,
            restStartDate: Date?,
            restEndDate: Date?
        ) {
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

- [ ] **Step 2: Write the failing test**

Create `5x5ive/5x5iveTests/WorkoutActivityAttributesTests.swift`:

```swift
import Testing
@testable import _x5ive

struct WorkoutActivityAttributesTests {
    @Test func contentStateEqualityReflectsAllFields() {
        let base = WorkoutActivityAttributes.ContentState(
            currentExerciseName: "Squat",
            completedSets: 2,
            totalSets: 5,
            nextExerciseName: "Bench Press",
            restStartDate: nil,
            restEndDate: nil
        )
        let same = base
        var different = base
        different.completedSets = 3

        #expect(base == same)
        #expect(base != different)
    }

    @Test func attributesCarryTheWorkoutType() {
        let attributes = WorkoutActivityAttributes(workoutTypeRawValue: "A")
        #expect(attributes.workoutTypeRawValue == "A")
    }
}
```

Note: `@testable import _x5ive` matches this project's actual app module name (the app's Swift module is named after its target, `_x5ive`, not `5x5ive` — numeric-leading identifiers aren't valid Swift module names, which is also why the source files are prefixed `_x5ive` throughout, e.g. `_x5iveApp.swift`, `_x5iveTests.swift`). If this import fails to resolve, run `xcodebuild -showBuildSettings -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive 2>/dev/null | grep -m1 PRODUCT_MODULE_NAME` to confirm the exact module name and adjust.

- [ ] **Step 3: Run test to verify it fails**

Run: `xcodebuild test -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:5x5iveTests/WorkoutActivityAttributesTests 2>&1 | tail -40`
Expected: FAIL — build error, `cannot find type 'WorkoutActivityAttributes' in scope` (the type doesn't exist in the app target's compiled sources yet).

- [ ] **Step 4: Add the file to both targets via script**

Create `/tmp/add_shared_attributes.rb` (scratch, do not commit):

```ruby
require 'xcodeproj'

project_path = '5x5ive/5x5ive.xcodeproj'
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == '5x5ive' }
widget_target = project.targets.find { |t| t.name == '5x5iveWidget' }
raise 'expected targets not found — did Task 1 run?' unless app_target && widget_target

widget_group = project.main_group.find_subpath('5x5iveWidget', false)
raise '5x5iveWidget group not found — did Task 1 run?' unless widget_group

file_ref = widget_group.new_file('WorkoutActivityAttributes.swift')
app_target.add_file_references([file_ref])
widget_target.add_file_references([file_ref])

project.save

puts 'Done.'
```

Run: `ruby /tmp/add_shared_attributes.rb`
Expected: `Done.`

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:5x5iveTests/WorkoutActivityAttributesTests 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **`, both new tests passing.

- [ ] **Step 6: Build the whole app target to confirm the widget extension still compiles with the new shared file too**

Run: `xcodebuild build -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add 5x5ive/5x5ive.xcodeproj/project.pbxproj 5x5ive/5x5iveWidget/WorkoutActivityAttributes.swift 5x5ive/5x5iveTests/WorkoutActivityAttributesTests.swift
git commit -m "feat: add shared WorkoutActivityAttributes type for the Live Activity"
```

Then delete the scratch script: `rm /tmp/add_shared_attributes.rb`

---

### Task 3: `LiveActivityManager` (app target)

**Files:**
- Create: `5x5ive/5x5ive/LiveActivityManager.swift`

**Interfaces:**
- Consumes: `WorkoutActivityAttributes`, `WorkoutActivityAttributes.ContentState` (Task 2).
- Produces: `LiveActivityManager.shared: LiveActivityManager`, `func startIfNeeded(workoutTypeRawValue: String, state: WorkoutActivityAttributes.ContentState)`, `func update(state: WorkoutActivityAttributes.ContentState)`, `func end()`. Task 5 calls all three.

This file goes directly in `5x5ive/5x5ive/` (the app target's synchronized folder) — no pbxproj edit needed, it's picked up automatically like every other app-target file added in the previous feature (`NotificationManager.swift`, `ActiveWorkoutBar.swift`, etc.).

No dedicated unit test — matches the existing `NotificationManager`/`HealthKitManager` precedent (a thin, unmockable wrapper around a system framework). Verified by a clean build here; exercised for real in Task 6's manual verification.

- [ ] **Step 1: Create the file**

Create `5x5ive/5x5ive/LiveActivityManager.swift`:

```swift
import ActivityKit

/// Owns the single Live Activity this app ever runs at a time, showing the
/// active workout's current exercise, its set progress, the next exercise,
/// and a rest countdown when one is running. Mirrors
/// `NotificationManager`'s shape: a `@MainActor` singleton wrapping a
/// system framework, every failure swallowed — an unavailable or denied
/// Live Activity is not crash-worthy.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<WorkoutActivityAttributes>?

    private init() {}

    /// No-ops if a matching system Activity already exists — covers a
    /// fresh workout start, reopening a minimized workout, and an app
    /// relaunch with an existing active session, all from one call site
    /// (`ActiveWorkoutView.onAppear`).
    func startIfNeeded(workoutTypeRawValue: String, state: WorkoutActivityAttributes.ContentState) {
        if let existing = Activity<WorkoutActivityAttributes>.activities.first {
            currentActivity = existing
            return
        }
        guard currentActivity == nil else { return }

        let attributes = WorkoutActivityAttributes(workoutTypeRawValue: workoutTypeRawValue)
        let content = ActivityContent(state: state, staleDate: staleDate(for: state))
        currentActivity = try? Activity.request(attributes: attributes, content: content)
    }

    func update(state: WorkoutActivityAttributes.ContentState) {
        guard let currentActivity else { return }
        let content = ActivityContent(state: state, staleDate: staleDate(for: state))
        Task { await currentActivity.update(content) }
    }

    func end() {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// A rest window re-arms the stale date a couple minutes past its own
    /// end; otherwise a shorter fixed buffer, re-armed on every update — so
    /// an actively-updating workout never goes stale, while one whose app
    /// process died stops getting re-armed and dims on schedule.
    private func staleDate(for state: WorkoutActivityAttributes.ContentState) -> Date {
        if let restEnd = state.restEndDate {
            return restEnd.addingTimeInterval(120)
        }
        return Date.now.addingTimeInterval(90)
    }
}
```

- [ ] **Step 2: Build the app target to verify it compiles**

Run: `xcodebuild build -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add 5x5ive/5x5ive/LiveActivityManager.swift
git commit -m "feat: add LiveActivityManager to own the workout Live Activity"
```

---

### Task 4: The real Live Activity UI (Lock Screen + Dynamic Island)

**Files:**
- Create: `5x5ive/5x5iveWidget/WorkoutLiveActivityWidget.swift`
- Modify: `5x5ive/5x5iveWidget/FiveByFiveWidgetBundle.swift`

**Interfaces:**
- Consumes: `WorkoutActivityAttributes`, `WorkoutActivityAttributes.ContentState` (Task 2).
- Produces: a `WorkoutLiveActivityWidget: Widget` registered in the widget bundle, so requesting an `Activity<WorkoutActivityAttributes>` (Task 3, wired in Task 5) actually renders something.

- [ ] **Step 1: Create the Live Activity widget**

Create `5x5ive/5x5iveWidget/WorkoutLiveActivityWidget.swift`:

```swift
import WidgetKit
import SwiftUI
import ActivityKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            lockScreenBanner(for: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.currentExerciseName)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    trailingContent(for: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let nextExerciseName = context.state.nextExerciseName {
                        Text("Next: \(nextExerciseName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Text(context.state.currentExerciseName)
                    .font(.caption2)
                    .lineLimit(1)
            } compactTrailing: {
                trailingContent(for: context.state)
                    .font(.caption2)
            } minimal: {
                if let restEndDate = context.state.restEndDate {
                    Text(timerInterval: Date.now...restEndDate, countsDown: true)
                        .font(.caption2)
                        .monospacedDigit()
                } else {
                    Text("\(context.state.completedSets)/\(context.state.totalSets)")
                        .font(.caption2)
                }
            }
        }
    }

    @ViewBuilder
    private func lockScreenBanner(for state: WorkoutActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(state.currentExerciseName)
                    .font(.headline)
                Spacer()
                Text("\(state.completedSets)/\(state.totalSets) sets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let restStartDate = state.restStartDate, let restEndDate = state.restEndDate {
                Text(timerInterval: restStartDate...restEndDate, countsDown: true)
                    .font(.title2)
                    .monospacedDigit()
            }
            if let nextExerciseName = state.nextExerciseName {
                Text("Next: \(nextExerciseName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func trailingContent(for state: WorkoutActivityAttributes.ContentState) -> some View {
        if let restEndDate = state.restEndDate {
            Text(timerInterval: Date.now...restEndDate, countsDown: true)
                .monospacedDigit()
        } else {
            Text("\(state.completedSets)/\(state.totalSets)")
        }
    }
}
```

Note: `Text(timerInterval:countsDown:)` requires the interval's `lowerBound` to be at or before "now" and `upperBound` in the future to render a live countdown — using `Date.now...restEndDate` for the compact/minimal states (which get re-evaluated by the system each render) and the actual `restStartDate...restEndDate` for the Lock Screen banner (which is fine since `restStartDate` is always in the past relative to when the widget is rendered) are both valid uses of this API.

- [ ] **Step 2: Register it in the widget bundle**

Modify `5x5ive/5x5iveWidget/FiveByFiveWidgetBundle.swift` — replace the `body`:

```swift
    var body: some Widget {
        PlaceholderWidget()
    }
```

with:

```swift
    var body: some Widget {
        WorkoutLiveActivityWidget()
    }
```

(Leave `PlaceholderWidget`, `PlaceholderEntry`, and `PlaceholderProvider` defined in the file — removing them isn't necessary and they cost nothing; only the bundle's `body` needs to stop instantiating `PlaceholderWidget`.)

- [ ] **Step 3: Add the new file to the widget target**

Create `/tmp/add_live_activity_widget.rb` (scratch, do not commit):

```ruby
require 'xcodeproj'

project_path = '5x5ive/5x5ive.xcodeproj'
project = Xcodeproj::Project.open(project_path)

widget_target = project.targets.find { |t| t.name == '5x5iveWidget' }
raise 'expected target not found — did Task 1 run?' unless widget_target

widget_group = project.main_group.find_subpath('5x5iveWidget', false)
raise '5x5iveWidget group not found — did Task 1 run?' unless widget_group

file_ref = widget_group.new_file('WorkoutLiveActivityWidget.swift')
widget_target.add_file_references([file_ref])

project.save

puts 'Done.'
```

Run: `ruby /tmp/add_live_activity_widget.rb`
Expected: `Done.`

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild build -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' 2>&1 | tail -40`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add 5x5ive/5x5ive.xcodeproj/project.pbxproj 5x5ive/5x5iveWidget/WorkoutLiveActivityWidget.swift 5x5ive/5x5iveWidget/FiveByFiveWidgetBundle.swift
git commit -m "feat: add the workout Live Activity's Lock Screen and Dynamic Island UI"
```

Then delete the scratch script: `rm /tmp/add_live_activity_widget.rb`

---

### Task 5: Wire the trigger points into `ActiveWorkoutView`

**Files:**
- Modify: `5x5ive/5x5ive/ActiveWorkoutView.swift`

**Interfaces:**
- Consumes: `LiveActivityManager.shared.startIfNeeded(workoutTypeRawValue:state:)`, `.update(state:)`, `.end()` (Task 3); `WorkoutActivityAttributes.ContentState` (Task 2).
- Produces: nothing new for later tasks — this is the last functional piece; Task 6 is manual verification only.

The current file (read it first — it's changed since this plan was written, most recently to add rest-state persistence and notification-permission requesting) has these relevant pieces: `logs: [ExerciseLog]` (computed from `session.sortedLogs`), `viewModel.expandedLogID: PersistentIdentifier?` (the currently-focused exercise), `viewModel.activeRest: ActiveWorkoutViewModel.ActiveRest?`, `.onAppear { viewModel.focusFirstIncomplete(in: logs); restoreOrClearPersistedRest() }`, `.onChange(of: viewModel.activeRest) { _, newValue in syncRestToSession(newValue) }`, `.onChange(of: viewModel.completion?.logID) { ... }`, `finish()`, `cancel()`.

- [ ] **Step 1: Add a `ContentState` builder**

Add this private method to `ActiveWorkoutView` (anywhere in the `// MARK: Actions` section is fine):

```swift
    /// Builds the Live Activity's content state from current view state.
    /// "Current exercise" is whichever log is focused (falls back to the
    /// first log if none is, matching `focusFirstIncomplete`'s own
    /// fallback); "next" is the log immediately after it by `order`.
    private func currentActivityState() -> WorkoutActivityAttributes.ContentState? {
        // `logs` (= `session.sortedLogs`) is already sorted by `order`.
        guard let currentLog = logs.first(where: { $0.persistentModelID == viewModel.expandedLogID }) ?? logs.first else {
            return nil
        }
        let nextLog = logs.first { $0.order > currentLog.order }
        let rest = viewModel.activeRest

        return WorkoutActivityAttributes.ContentState(
            currentExerciseName: currentLog.exercise?.name ?? "",
            completedSets: currentLog.loggedSetCount,
            totalSets: currentLog.sets.count,
            nextExerciseName: nextLog?.exercise?.name,
            restStartDate: rest?.startDate,
            restEndDate: rest?.endDate
        )
    }
```

- [ ] **Step 2: Start (or resume) the Live Activity on appear**

Modify the `.onAppear` block in `body`:

```swift
        .onAppear {
            viewModel.focusFirstIncomplete(in: logs)
            restoreOrClearPersistedRest()
        }
```

to:

```swift
        .onAppear {
            viewModel.focusFirstIncomplete(in: logs)
            restoreOrClearPersistedRest()
            if let state = currentActivityState() {
                LiveActivityManager.shared.startIfNeeded(workoutTypeRawValue: session.workoutType.rawValue, state: state)
            }
        }
```

- [ ] **Step 3: Update on rest change and on exercise advance**

Modify the `.onChange(of: viewModel.activeRest)` block:

```swift
        .onChange(of: viewModel.activeRest) { _, newValue in
            syncRestToSession(newValue)
        }
```

to:

```swift
        .onChange(of: viewModel.activeRest) { _, newValue in
            syncRestToSession(newValue)
            if let state = currentActivityState() {
                LiveActivityManager.shared.update(state: state)
            }
        }
```

Modify the `.onChange(of: viewModel.completion?.logID)` block:

```swift
        .onChange(of: viewModel.completion?.logID) { _, _ in
            // Auto-advance: focus moves as soon as an exercise finishes.
            withAnimation(.snappy) { viewModel.focusFirstIncomplete(in: logs) }
        }
```

to:

```swift
        .onChange(of: viewModel.completion?.logID) { _, _ in
            // Auto-advance: focus moves as soon as an exercise finishes.
            withAnimation(.snappy) { viewModel.focusFirstIncomplete(in: logs) }
            if let state = currentActivityState() {
                LiveActivityManager.shared.update(state: state)
            }
        }
```

- [ ] **Step 4: End the Live Activity on finish and cancel**

Modify `finish()`:

```swift
    private func finish() -> XPAward? {
        guard let award = try? WorkoutSessionService.finishWorkout(session, in: modelContext) else { return nil }
        #if canImport(HealthKit) && os(iOS)
        let start = session.startedAt
        let end = session.finishedAt ?? .now
        Task { await HealthKitManager.shared.saveWorkout(start: start, end: end) }
        #endif
        return award
    }
```

to:

```swift
    private func finish() -> XPAward? {
        guard let award = try? WorkoutSessionService.finishWorkout(session, in: modelContext) else { return nil }
        #if canImport(HealthKit) && os(iOS)
        let start = session.startedAt
        let end = session.finishedAt ?? .now
        Task { await HealthKitManager.shared.saveWorkout(start: start, end: end) }
        #endif
        LiveActivityManager.shared.end()
        return award
    }
```

Modify `cancel()`:

```swift
    private func cancel() {
        try? WorkoutSessionService.cancelWorkout(session, in: modelContext)
        dismiss()
    }
```

to:

```swift
    private func cancel() {
        try? WorkoutSessionService.cancelWorkout(session, in: modelContext)
        LiveActivityManager.shared.end()
        dismiss()
    }
```

- [ ] **Step 5: Build the app target**

Run: `xcodebuild build -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Run the existing UI test suite to confirm no regressions**

Run: `xcodebuild test -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' 2>&1 | tail -60`
Expected: every existing test (SwoleData tests run separately via `swift test`; this is the `5x5iveTests`/`5x5iveUITests` targets) still passes. Live Activities don't require special permission to *request* in a way that would block a UI test run (the system may silently deny if Live Activities are off in Settings, which `LiveActivityManager` already treats as a no-op), so no existing test should be affected by this change.

- [ ] **Step 7: Commit**

```bash
git add 5x5ive/5x5ive/ActiveWorkoutView.swift
git commit -m "feat: drive the workout Live Activity from ActiveWorkoutView's state changes"
```

---

### Task 6: Manual verification

**Files:** none — this task produces no code changes, only a verification report.

**Interfaces:**
- Consumes: the complete feature (Tasks 1-5).

This is the task called for by the spec's Testing section: XCUITest cannot inspect Live Activity or Dynamic Island content (it renders in a separate system process outside the app's own accessibility tree), so this coverage is necessarily manual. Perform every check below and write the results into your report — do not skip a check because an earlier one passed; the point is to observe the actual rendered content, not just confirm nothing crashed.

- [ ] **Step 1: Fresh install and launch**

```bash
xcrun simctl list devices | grep "iPhone 17 Pro Max"
# note the UDID, then:
xcrun simctl boot <UDID> 2>&1 || true
open -a Simulator --args -CurrentDeviceUDID <UDID>
xcodebuild build -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'id=<UDID>' 2>&1 | tail -10
APP_PATH=$(xcodebuild -showBuildSettings -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'id=<UDID>' 2>/dev/null | grep -m1 'CODESIGNING_FOLDER_PATH' | awk '{print $3}')
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist")
xcrun simctl install <UDID> "$APP_PATH"
xcrun simctl launch <UDID> "$BUNDLE_ID"
```

- [ ] **Step 2: Start a workout and confirm the Live Activity requests successfully**

In the running app (use the Simulator window, or `xcrun simctl io <UDID> screenshot` to check state), tap "Start Workout A" (or whichever workout type is next). Live Activities appear in the Dynamic Island immediately (no lock needed) on a Dynamic-Island-capable simulator — take a screenshot:

```bash
xcrun simctl io <UDID> screenshot /tmp/live-activity-dynamic-island.png
```

Look at the screenshot. Expected: a compact Dynamic Island pill showing the first exercise's name.

- [ ] **Step 3: Lock the screen and confirm the Lock Screen banner**

```bash
xcrun simctl io <UDID> screenshot /tmp/before-lock.png
osascript -e 'tell application "Simulator" to activate' -e 'tell application "System Events" to keystroke "l" using command down'
sleep 1
xcrun simctl io <UDID> screenshot /tmp/lock-screen-banner.png
```

Look at `/tmp/lock-screen-banner.png`. Expected: the workout's Live Activity banner is visible on the Lock Screen, showing the current exercise name and "0/N sets" (or however many are logged).

- [ ] **Step 4: Log a set that starts a rest timer, confirm the countdown renders**

Unlock (`osascript -e 'tell application "System Events" to keystroke "l" using command down'` toggles lock/unlock the same way, or swipe up via `xcrun simctl io <UDID>` isn't directly scriptable for swipe gestures — using the Simulator app's own UI via a click may be simpler here; if scripting the unlock proves unreliable, do this step interactively and note that in your report). Tap a set tile to log it (matching the existing UI test's pattern: tap once, wait ~2s past the 1.5s settle debounce). Take another Lock Screen screenshot after re-locking. Expected: the banner now shows a live countdown timer that visibly ticks down across two screenshots taken a few seconds apart.

- [ ] **Step 5: Force-quit and confirm staleness behavior**

```bash
xcrun simctl terminate <UDID> "$BUNDLE_ID"
```

Wait past the staleness window noted in `LiveActivityManager` (90 seconds if not resting, or ~2 minutes past the rest end date if resting — wait the longer of the two based on what state the workout was in when you terminated it), then screenshot the Lock Screen again. Expected: the Live Activity is either visibly dimmed/stale-styled or has disappeared entirely — not still showing fresh, un-stale content for a process that's no longer running.

- [ ] **Step 6: Relaunch mid-workout and confirm resumption**

```bash
xcrun simctl launch <UDID> "$BUNDLE_ID"
```

The app should reopen to the still-in-progress workout (existing behavior, unrelated to this feature) and — since the prior Activity ended from staleness — `startIfNeeded` should request a fresh one from `ActiveWorkoutView.onAppear`. Screenshot the Dynamic Island again to confirm a new Live Activity is showing current state, not stuck on stale data from before the relaunch.

- [ ] **Step 7: Finish or cancel the workout, confirm the Live Activity ends**

Tap "Cancel" (or complete the workout), confirm via the alert, then screenshot the Lock Screen / Dynamic Island once more. Expected: no Live Activity is present at all — `.end()` fired from `cancel()`/`finish()`.

- [ ] **Step 8: Write the verification report**

Summarize, for each of Steps 2-7, what you observed (pass/fail/ambiguous) with the screenshot paths as evidence. If any step didn't behave as expected, describe exactly what you saw instead — this becomes the input to a fix round, not a blocker to stop at silently.

---

## Final verification

- [ ] **All 5 code tasks (1-5) committed**, each building `** BUILD SUCCEEDED **` at the time of its own commit.
- [ ] **`cd SwoleData && swift test`** still passes in full (this feature must not have touched `SwoleData` at all — confirm the diff across all 5 tasks never touches `SwoleData/`).
- [ ] **`xcodebuild test -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'`** passes in full, including the new `WorkoutActivityAttributesTests`.
- [ ] **Task 6's manual verification report** shows all 6 checks (Steps 2-7) behaving as expected, or documents precisely what didn't and why.
