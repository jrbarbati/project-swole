# HealthKit Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read the user's bodyweight from Apple Health to estimate calories burned, and write a completed workout to Apple Health when a live workout finishes.

**Architecture:** A pure, cross-platform calorie-estimate function lives in `SwoleData` (unit-testable, no HealthKit import). All HealthKit API calls live in a new app-target-only `HealthKitManager`, compiled out entirely on macOS/xrOS via `#if canImport(HealthKit) && os(iOS)`. `ActiveWorkoutView.finish()` fires the sync as an untracked `Task` after `WorkoutSessionService.finishWorkout` succeeds — Health sync can never affect the workout-finish flow's return value or UI.

**Tech Stack:** Swift 6.3 / SwiftUI / SwiftData / HealthKit (iOS 26.5+ deployment target). `HKWorkoutBuilder` async API for retroactive (non-live) workout writes.

**Spec:** `docs/superpowers/specs/2026-08-29-healthkit-integration-design.md`

## Global Constraints

- `SwoleData` package must never import HealthKit — it has macOS-hosted unit tests (`swift test` runs on macOS).
- All HealthKit-touching code wrapped in `#if canImport(HealthKit) && os(iOS)` — must compile away to nothing on macOS/xrOS builds.
- No changes to `WorkoutSession` or `WorkoutSessionService`'s public behavior/signatures.
- Permission requested only via `HKHealthStore.requestAuthorization`, triggered the first time a workout finishes — no onboarding screen, no Settings toggle.
- Every HealthKit failure (denied, unavailable, no data) is swallowed silently — never surfaces to the user or blocks workout-finish.
- App target's Xcode project uses a `PBXFileSystemSynchronizedRootGroup` for the `5x5ive` folder — new `.swift` files placed in `5x5ive/5x5ive/` are picked up automatically, no `project.pbxproj` source-list edit needed. Build-setting and entitlements changes still require editing `project.pbxproj` directly.
- App target's two build configs in `project.pbxproj` are `04176071303FFE2D00ACCEDC` (Debug) and `04176072303FFE2D00ACCEDC` (Release) — confirmed via `buildConfigurationList = 04176070303FFE2D00ACCEDC` on the `5x5ive` `PBXNativeTarget`. Test targets (`5x5iveTests`, `5x5iveUITests`) are untouched by this plan.
- Verify builds with: `xcodebuild -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' build` (iOS) and `xcodebuild -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=macOS' build` (macOS gate check). Run both from `/Users/josephbarbati/dev/project-swole`.
- SwoleData tests: `cd SwoleData && swift test`.

---

### Task 1: WorkoutEnergyEstimate pure calculator

**Files:**
- Create: `SwoleData/Sources/SwoleData/WorkoutEnergyEstimate.swift`
- Test: `SwoleData/Tests/SwoleDataTests/WorkoutEnergyEstimateTests.swift`

**Interfaces:**
- Produces: `WorkoutEnergyEstimate.strengthTrainingMET: Double` (= 5.0), `WorkoutEnergyEstimate.kilocalories(bodyWeightKg: Double, duration: TimeInterval, met: Double = strengthTrainingMET) -> Double`. Task 3 (`HealthKitManager`) calls this exact signature.

- [ ] **Step 1: Write the failing tests**

```swift
// SwoleData/Tests/SwoleDataTests/WorkoutEnergyEstimateTests.swift
import Testing
@testable import SwoleData

@Test func knownCombinationProducesExpectedKilocalories() {
    // 5.0 MET * 80kg * 1 hour = 400 kcal
    let kcal = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 80, duration: 3600)
    #expect(abs(kcal - 400) < 0.001)
}

@Test func zeroDurationProducesZeroKilocalories() {
    let kcal = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 80, duration: 0)
    #expect(kcal == 0)
}

@Test func scalesLinearlyWithBodyWeight() {
    let base = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 80, duration: 3600)
    let doubled = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 160, duration: 3600)
    #expect(abs(doubled - base * 2) < 0.001)
}

@Test func scalesLinearlyWithDuration() {
    let base = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 80, duration: 3600)
    let doubled = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 80, duration: 7200)
    #expect(abs(doubled - base * 2) < 0.001)
}

@Test func customMETOverridesDefault() {
    let kcal = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 80, duration: 3600, met: 1.0)
    #expect(abs(kcal - 80) < 0.001)
}
```

Matches this package's existing convention (see `XPCalculatorTests.swift`): flat top-level `@Test func`s using Swift Testing's `#expect`, no `XCTestCase`/`@Suite` wrapper.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SwoleData && swift test --filter WorkoutEnergyEstimateTests`
Expected: FAIL to build — `WorkoutEnergyEstimate` does not exist.

- [ ] **Step 3: Write the implementation**

```swift
// SwoleData/Sources/SwoleData/WorkoutEnergyEstimate.swift
import Foundation

public enum WorkoutEnergyEstimate {
    /// MET for free-weight resistance training (moderate-vigorous, ACSM tables).
    public static let strengthTrainingMET = 5.0

    /// kcal = MET * bodyweight(kg) * duration(hours).
    public static func kilocalories(bodyWeightKg: Double, duration: TimeInterval, met: Double = strengthTrainingMET) -> Double {
        met * bodyWeightKg * (duration / 3600)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SwoleData && swift test --filter WorkoutEnergyEstimateTests`
Expected: PASS, all 5 tests green.

- [ ] **Step 5: Run the full SwoleData suite to confirm no regressions**

Run: `cd SwoleData && swift test`
Expected: PASS, all existing tests still green.

- [ ] **Step 6: Commit**

```bash
git add SwoleData/Sources/SwoleData/WorkoutEnergyEstimate.swift SwoleData/Tests/SwoleDataTests/WorkoutEnergyEstimateTests.swift
git commit -m "feat: add pure calorie-estimate calculator for Health workout writes"
```

---

### Task 2: HealthKit capability plumbing + HealthKitManager

**Files:**
- Create: `5x5ive/5x5ive/5x5ive.entitlements`
- Create: `5x5ive/5x5ive/HealthKitManager.swift`
- Modify: `5x5ive/5x5ive.xcodeproj/project.pbxproj` (app target's Debug config `04176071303FFE2D00ACCEDC` and Release config `04176072303FFE2D00ACCEDC`)

**Interfaces:**
- Consumes: `WorkoutEnergyEstimate.kilocalories(bodyWeightKg:duration:met:)` from Task 1.
- Produces: `HealthKitManager.shared.saveWorkout(start: Date, end: Date) async` — Task 3's call site uses this exact signature.

- [ ] **Step 1: Create the entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.healthkit</key>
	<true/>
</dict>
</plist>
```

Save as `5x5ive/5x5ive/5x5ive.entitlements`.

- [ ] **Step 2: Wire the entitlements file and usage-description keys into project.pbxproj**

Open `5x5ive/5x5ive.xcodeproj/project.pbxproj`. In the Debug config block starting `04176071303FFE2D00ACCEDC /* Debug */` (app target), add these lines inside `buildSettings` (alongside the existing `"INFOPLIST_KEY_..."` entries, same SDK-scoping style already used there for `UIApplicationSceneManifest_Generation` etc — HealthKit is iOS-only so scope both the entitlements file and the usage strings to `iphoneos`/`iphonesimulator` only, leaving macOS/xrOS untouched):

```
				"CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]" = 5x5ive/5x5ive.entitlements;
				"CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]" = 5x5ive/5x5ive.entitlements;
				"INFOPLIST_KEY_NSHealthShareUsageDescription[sdk=iphoneos*]" = "Used to estimate calories burned during your workouts.";
				"INFOPLIST_KEY_NSHealthShareUsageDescription[sdk=iphonesimulator*]" = "Used to estimate calories burned during your workouts.";
				"INFOPLIST_KEY_NSHealthUpdateUsageDescription[sdk=iphoneos*]" = "Saves your finished workouts to Health.";
				"INFOPLIST_KEY_NSHealthUpdateUsageDescription[sdk=iphonesimulator*]" = "Saves your finished workouts to Health.";
```

Do the identical addition in the Release config block `04176072303FFE2D00ACCEDC /* Release */`. Do **not** touch `04176074303FFE2D00ACCEDC`/`04176075303FFE2D00ACCEDC` (5x5iveTests) or `04176077303FFE2D00ACCEDC`/`04176078303FFE2D00ACCEDC` (5x5iveUITests) — those targets don't need Health entitlements.

- [ ] **Step 3: Create HealthKitManager**

```swift
// 5x5ive/5x5ive/HealthKitManager.swift
#if canImport(HealthKit) && os(iOS)
import HealthKit
import SwoleData

@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    private var bodyMassType: HKQuantityType { HKQuantityType(.bodyMass) }
    private var energyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }
    private var workoutObjectType: HKObjectType { HKObjectType.workoutType() }

    /// Best-effort: writes one Health workout for a finished session. Every
    /// failure (unavailable, denied, no data) is swallowed — Health sync is a
    /// side effect that must never surface an error to the workout-finish flow.
    func saveWorkout(start: Date, end: Date) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(
                toShare: [workoutObjectType, energyType],
                read: [bodyMassType]
            )
        } catch {
            return
        }

        let energy = await latestBodyWeightKg().map {
            WorkoutEnergyEstimate.kilocalories(bodyWeightKg: $0, duration: end.timeIntervalSince(start))
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        do {
            try await builder.beginCollection(at: start)
            if let energy {
                let sample = HKQuantitySample(
                    type: energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energy),
                    start: start,
                    end: end
                )
                try await builder.addSamples([sample])
            }
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            return
        }
    }

    private func latestBodyWeightKg() async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMassType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                let sample = samples?.first as? HKQuantitySample
                continuation.resume(returning: sample?.quantity.doubleValue(for: .gramUnit(with: .kilo)))
            }
            store.execute(query)
        }
    }
}
#endif
```

- [ ] **Step 4: Build for iOS Simulator to confirm it compiles**

Run: `xcodebuild -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Build for macOS to confirm the platform gate compiles away cleanly and code signing isn't broken by the SDK-scoped entitlements**

Run: `xcodebuild -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`. If this fails on entitlements/code-signing, the `[sdk=...]` scoping in Step 2 was applied incorrectly — re-check that the plain (unscoped) `CODE_SIGN_ENTITLEMENTS` key was not also set.

- [ ] **Step 6: Commit**

```bash
git add 5x5ive/5x5ive/5x5ive.entitlements 5x5ive/5x5ive/HealthKitManager.swift 5x5ive/5x5ive.xcodeproj/project.pbxproj
git commit -m "feat: add HealthKit capability + manager for iOS builds"
```

---

### Task 3: Wire Health sync into the workout-finish flow

**Files:**
- Modify: `5x5ive/5x5ive/ActiveWorkoutView.swift:228` (`finish()`)

**Interfaces:**
- Consumes: `HealthKitManager.shared.saveWorkout(start: Date, end: Date) async` from Task 2; `session.startedAt`, `session.finishedAt` (existing `WorkoutSession` properties, unchanged).

- [ ] **Step 1: Update `finish()`**

Current code (`5x5ive/5x5ive/ActiveWorkoutView.swift:228-230`):

```swift
    private func finish() -> XPAward? {
        try? WorkoutSessionService.finishWorkout(session, in: modelContext)
    }
```

Replace with:

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

- [ ] **Step 2: Build for iOS Simulator**

Run: `xcodebuild -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Build for macOS to reconfirm the platform gate**

Run: `xcodebuild -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the existing 5x5iveTests/UITests to confirm no regression in the finish flow**

Run: `xcodebuild -project 5x5ive/5x5ive.xcodeproj -scheme 5x5ive -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: existing tests pass (the Health sync `Task` is fire-and-forget and untracked, so it cannot fail or delay these tests).

- [ ] **Step 5: Manual verification in iOS Simulator**

1. Boot the "iPhone 17" simulator (`xcrun simctl boot F21438AD-AC4B-4F87-BCEC-91AFA4FBCDE9` if not already booted) and run the app (`xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17' build` then install/launch, or run from Xcode).
2. Start and finish a workout in the app. Accept the Health permission prompt when it appears (share workout + active energy, read body mass).
3. Open the Health app in the simulator → Browse → Activity → Workouts. Confirm a new "Traditional Strength Training" entry appears with the correct duration and start time. If no body-mass sample exists yet in the simulator's Health store, the entry will have no calorie figure — that's expected per the spec (energy is best-effort); to see the calorie figure, add a body mass sample first via Health app → Browse → Body Measurements → Weight → Add Data, then finish another workout.
4. Deny the permission prompt on a second, freshly-reset simulator (or reset Health permissions for the app via Settings → Health → Data Access & Devices → 5x5ive → Turn Off All) and confirm finishing a workout still completes normally (summary screen, XP award) with no error surfaced.

- [ ] **Step 6: Commit**

```bash
git add 5x5ive/5x5ive/ActiveWorkoutView.swift
git commit -m "feat: sync finished workouts to Apple Health"
```

## Self-Review Notes

- Spec coverage: read (bodyweight → calorie estimate) — Task 2 `latestBodyWeightKg` + `WorkoutEnergyEstimate`; write (HKWorkout with duration/type/energy) — Task 2 `saveWorkout`; permission-on-finish, no toggle — Task 3 call site, no Settings changes anywhere in this plan; platform gate — `#if canImport(HealthKit) && os(iOS)` in Tasks 2–3, verified by the macOS build step in both; SwoleData stays HealthKit-free — Task 1 has zero HealthKit import, confirmed by `swift test` running on macOS in Task 1 Step 5. All spec requirements have a task.
- No placeholders — every step has real, complete code.
- Signature consistency checked: `WorkoutEnergyEstimate.kilocalories(bodyWeightKg:duration:met:)` (Task 1) matches its one call site in `HealthKitManager.saveWorkout` (Task 2); `HealthKitManager.shared.saveWorkout(start:end:)` (Task 2) matches its one call site in `ActiveWorkoutView.finish()` (Task 3).
