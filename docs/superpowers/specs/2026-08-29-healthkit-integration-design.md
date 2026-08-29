# Apple Health integration

## Problem

Workouts finished in the app go nowhere else — no bodyweight-aware calorie estimate, no entry in Apple Health, no credit toward Activity rings. Read the user's current bodyweight from Health and write a completed workout (with an estimated active-energy figure) when a workout finishes.

## Requirements

- Read: latest body mass sample from Health.
- Write: one Health workout per finished live workout, with start/end time, activity type, and an estimated active-energy-burned figure derived from bodyweight + duration.
- Permission is requested the first time a workout finishes (no separate onboarding step, no Settings toggle). If denied, the app never prompts again that session and finishing workouts continues to work normally — Health sync is silently absent.
- The app also builds for macOS and visionOS (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx xros xrsimulator`) where HealthKit isn't usable the same way. The whole feature must compile away to nothing on those platforms rather than being force-unwrapped or crashing.
- `SwoleData` is a plain Swift package with macOS-hosted unit tests (`SwoleData/.build/arm64-apple-macosx`) — it must not import HealthKit. Any HealthKit-touching code lives in the app target only.
- No change to `WorkoutSession`/`WorkoutSessionService`'s public behavior — Health sync is triggered from the app-view layer, after `finishWorkout` succeeds, as a fire-and-forget side effect that cannot fail the workout-finish flow.

## Design

### Energy estimate (SwoleData — pure, testable)

```swift
// SwoleData/Sources/SwoleData/WorkoutEnergyEstimate.swift
public enum WorkoutEnergyEstimate {
    /// MET for free-weight resistance training (moderate-vigorous, ACSM tables).
    public static let strengthTrainingMET = 5.0

    /// kcal = MET * bodyweight(kg) * duration(hours)
    public static func kilocalories(bodyWeightKg: Double, duration: TimeInterval, met: Double = strengthTrainingMET) -> Double {
        met * bodyWeightKg * (duration / 3600)
    }
}
```

No HealthKit dependency — just the standard MET formula. Fully unit-testable on any platform.

### HealthKitManager (app target only)

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
    private var workoutType: HKObjectType { HKObjectType.workoutType() }

    /// Best-effort: writes one Health workout for a finished session. Every
    /// failure (unavailable, denied, no data) is swallowed — Health sync is a
    /// side effect that must never surface an error to the workout-finish flow.
    func saveWorkout(start: Date, end: Date) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(
                toShare: [workoutType, energyType],
                read: [bodyMassType]
            )
        } catch {
            return
        }

        let energy = await latestBodyWeightKg().map {
            WorkoutEnergyEstimate.kilocalories(bodyWeightKg: $0, duration: end.timeIntervalSince(start))
        }

        let builder = HKWorkoutBuilder(
            healthStore: store,
            configuration: {
                let config = HKWorkoutConfiguration()
                config.activityType = .traditionalStrengthTraining
                config.locationType = .indoor
                return config
            }(),
            device: .local()
        )

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

### Call site

`ActiveWorkoutView.finish()` (`5x5ive/5x5ive/ActiveWorkoutView.swift:228`):

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

Fire-and-forget: the summary/XP-reveal UI proceeds identically whether Health sync succeeds, fails, or is skipped entirely.

### Capability plumbing

- New `5x5ive/5x5ive/5x5ive.entitlements`:
  ```xml
  <key>com.apple.developer.healthkit</key>
  <true/>
  ```
  Wired via `CODE_SIGN_ENTITLEMENTS = 5x5ive/5x5ive.entitlements` on the app target's Debug and Release build configs only (not the test targets).
- Two new build settings on the app target (project uses `GENERATE_INFOPLIST_FILE`, so keys are injected via `INFOPLIST_KEY_*` rather than a manual plist):
  - `INFOPLIST_KEY_NSHealthShareUsageDescription = "Used to estimate calories burned during your workouts."`
  - `INFOPLIST_KEY_NSHealthUpdateUsageDescription = "Saves your finished workouts to Health."`

### Platform gate

Everything HealthKit-touching is wrapped in `#if canImport(HealthKit) && os(iOS)`. On macOS/xrOS builds `HealthKitManager.swift` compiles to an empty file and the call site's `Task { ... }` block disappears entirely — no stub, no runtime check needed since it's compiled out.

## Files touched

- `SwoleData/Sources/SwoleData/WorkoutEnergyEstimate.swift` — new pure calculator.
- `5x5ive/5x5ive/HealthKitManager.swift` — new, iOS-only.
- `5x5ive/5x5ive/ActiveWorkoutView.swift` — trigger Health sync in `finish()`.
- `5x5ive/5x5ive/5x5ive.entitlements` — new.
- `5x5ive/5x5ive.xcodeproj/project.pbxproj` — `CODE_SIGN_ENTITLEMENTS` + two `INFOPLIST_KEY_*` build settings on the app target.

## Testing

- `WorkoutEnergyEstimateTests` (SwoleData): known MET/weight/duration combos produce expected kcal; zero duration → 0 kcal; scales linearly with weight and with duration.
- `HealthKitManager` itself: no unit test (framework side effects, no protocol seam worth adding for a single best-effort call site). Verified manually in iOS Simulator (Health.app is present there): finish a workout, accept the permission prompt, confirm a Functional/Traditional Strength Training entry appears in Health with a plausible calorie figure; re-run with permission denied and confirm the workout-finish flow is unaffected.
- Full `xcodebuild` for the macOS destination (or `swift test` in `SwoleData`) after the change, to confirm the platform gate keeps the cross-platform package and macOS/xrOS app builds green.

## Out of scope

- Bodyweight display anywhere in-app — read is calorie-estimate-only, per requirements.
- A Settings toggle or any re-request affordance if the user denies permission — matches the "prompt on finish, no toggle" decision; recoverable only via the system Health app's own per-app permission screen.
- Manually-entered workouts (`ManualWorkoutEntryView`) — those sessions are created already-finished and never pass through `ActiveWorkoutView.finish()`, so they're never synced to Health.
- Live `HKWorkoutSession`/heart-rate-based energy (would require a paired Apple Watch); the estimate here is a MET-formula approximation, not measured energy.
