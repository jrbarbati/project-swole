# 5x5 Tracker DB Schema (SwoleData Package) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the SwiftData model layer for the 5x5 workout tracker (from `docs/superpowers/specs/2026-08-27-5x5-tracker-db-schema-design.md`) as a standalone, fully unit-tested Swift package that a future Xcode iOS app target can depend on.

**Architecture:** A local Swift Package named `SwoleData` at the repo root contains all `@Model` classes, the derived progression/scheduling logic, and a standard-setup seeder. It targets iOS 17 / macOS 14 (SwiftData's minimum) and is tested entirely from the command line with `swift test` using in-memory `ModelContainer`s — no Xcode project or simulator required for this phase. The eventual iOS app adds this package as a local dependency and never touches SwiftData internals directly; it calls into `ProgressionCalculator`, `WorkoutScheduler`, and `StandardSeed`.

**Tech Stack:** Swift 6.3, SwiftData, Swift Testing (`import Testing`, not XCTest), Swift Package Manager.

---

## Task 1: Scaffold the SwoleData package

**Files:**
- Create: `SwoleData/Package.swift`
- Create: `SwoleData/Sources/SwoleData/SwoleData.swift` (generated, then trimmed to a placeholder)
- Create: `SwoleData/Tests/SwoleDataTests/` (generated, then emptied)

- [ ] **Step 1: Generate the package**

Run:
```bash
mkdir -p /Users/josephbarbati/dev/project-swole/SwoleData
cd /Users/josephbarbati/dev/project-swole/SwoleData
swift package init --type library --name SwoleData
```
Expected: creates `Package.swift`, `.gitignore`, `Sources/SwoleData/SwoleData.swift`, `Tests/SwoleDataTests/SwoleDataTests.swift`.

- [ ] **Step 2: Set platforms in Package.swift**

Replace the contents of `SwoleData/Package.swift` with:

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwoleData",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SwoleData", targets: ["SwoleData"]),
    ],
    targets: [
        .target(name: "SwoleData"),
        .testTarget(name: "SwoleDataTests", dependencies: ["SwoleData"]),
    ]
)
```

- [ ] **Step 3: Remove the test placeholder; trim the source placeholder**

SwiftPM errors with `target 'SwoleData' ... is empty` if a target has zero source
files, so the `Sources/SwoleData/SwoleData.swift` placeholder can't simply be
deleted yet — it stays until Task 2 adds the first real source file. The test
placeholder has no such constraint because Task 2 immediately adds a real test
file in the same task, so it can go now.

Run:
```bash
rm /Users/josephbarbati/dev/project-swole/SwoleData/Tests/SwoleDataTests/SwoleDataTests.swift
```

Replace the contents of `SwoleData/Sources/SwoleData/SwoleData.swift` with:

```swift
// Placeholder that keeps the SwoleData target non-empty (SwiftPM requires at
// least one source file per target) until Task 2 adds WorkoutEnums.swift and
// deletes this file.
```

- [ ] **Step 4: Verify the package builds**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
cd /Users/josephbarbati/dev/project-swole
git add SwoleData/Package.swift SwoleData/.gitignore SwoleData/Sources/SwoleData/SwoleData.swift
git commit -m "Scaffold SwoleData Swift package for iOS 17 / macOS 14"
```

---

## Task 2: Shared enums (WorkoutType, MeasurementUnit)

**Files:**
- Create: `SwoleData/Sources/SwoleData/WorkoutEnums.swift`
- Test: `SwoleData/Tests/SwoleDataTests/WorkoutEnumsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SwoleData/Tests/SwoleDataTests/WorkoutEnumsTests.swift`:

```swift
import Testing
@testable import SwoleData

@Test func workoutTypeHasExactlyAAndB() {
    #expect(WorkoutType.allCases == [.a, .b])
    #expect(WorkoutType.a.rawValue == "A")
    #expect(WorkoutType.b.rawValue == "B")
}

@Test func measurementUnitHasExactlyLbAndKg() {
    #expect(MeasurementUnit.allCases == [.lb, .kg])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter workoutTypeHasExactlyAAndB`
Expected: FAIL to build — `error: cannot find type 'WorkoutType' in scope`

- [ ] **Step 3: Write minimal implementation**

Delete the Task 1 source placeholder now that a real source file is landing
(this is the point where the target stops being at risk of the SwiftPM
"target is empty" error, since `WorkoutEnums.swift` takes its place):

```bash
rm /Users/josephbarbati/dev/project-swole/SwoleData/Sources/SwoleData/SwoleData.swift
```

Create `SwoleData/Sources/SwoleData/WorkoutEnums.swift`:

```swift
public enum WorkoutType: String, Codable, CaseIterable, Sendable {
    case a = "A"
    case b = "B"
}

public enum MeasurementUnit: String, Codable, CaseIterable, Sendable {
    case lb
    case kg
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: `Test run with 2 tests in 0 suites passed`

- [ ] **Step 5: Commit**

```bash
cd /Users/josephbarbati/dev/project-swole
git add SwoleData/Sources/SwoleData/WorkoutEnums.swift SwoleData/Sources/SwoleData/SwoleData.swift SwoleData/Tests/SwoleDataTests/WorkoutEnumsTests.swift
git commit -m "Add WorkoutType and MeasurementUnit enums"
```

---

## Task 3: Exercise model (global catalog)

**Files:**
- Create: `SwoleData/Sources/SwoleData/Exercise.swift`
- Test: `SwoleData/Tests/SwoleDataTests/ExerciseTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SwoleData/Tests/SwoleDataTests/ExerciseTests.swift`:

```swift
import Testing
import SwiftData
@testable import SwoleData

@Test func exerciseCanBeInsertedAndFetched() throws {
    let container = try ModelContainer(
        for: Exercise.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    context.insert(Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5))
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Exercise>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.name == "Squat")
    #expect(fetched.first?.defaultSetCount == 5)
    #expect(fetched.first?.defaultRepsPerSet == 5)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter exerciseCanBeInsertedAndFetched`
Expected: FAIL to build — `error: cannot find type 'Exercise' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `SwoleData/Sources/SwoleData/Exercise.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class Exercise {
    public var name: String
    public var defaultSetCount: Int
    public var defaultRepsPerSet: Int

    public init(name: String, defaultSetCount: Int, defaultRepsPerSet: Int) {
        self.name = name
        self.defaultSetCount = defaultSetCount
        self.defaultRepsPerSet = defaultRepsPerSet
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass (3 total so far)

- [ ] **Step 5: Commit**

```bash
cd /Users/josephbarbati/dev/project-swole
git add SwoleData/Sources/SwoleData/Exercise.swift SwoleData/Tests/SwoleDataTests/ExerciseTests.swift
git commit -m "Add Exercise model"
```

---

## Task 4: UserExerciseConfig model (per-user override)

**Files:**
- Create: `SwoleData/Sources/SwoleData/UserExerciseConfig.swift`
- Test: `SwoleData/Tests/SwoleDataTests/UserExerciseConfigTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SwoleData/Tests/SwoleDataTests/UserExerciseConfigTests.swift`:

```swift
import Testing
import SwiftData
@testable import SwoleData

@Test func userExerciseConfigLinksToItsExercise() throws {
    let container = try ModelContainer(
        for: Exercise.self, UserExerciseConfig.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    context.insert(UserExerciseConfig(
        exercise: squat,
        startingWeight: 45,
        weightIncrement: 5,
        setCount: 5,
        repsPerSet: 5,
        deloadThreshold: 3,
        deloadPercentage: 0.10
    ))
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<UserExerciseConfig>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.exercise?.name == "Squat")
    #expect(fetched.first?.startingWeight == 45)
    #expect(fetched.first?.weightIncrement == 5)
    #expect(fetched.first?.deloadThreshold == 3)
    #expect(fetched.first?.deloadPercentage == 0.10)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter userExerciseConfigLinksToItsExercise`
Expected: FAIL to build — `error: cannot find type 'UserExerciseConfig' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `SwoleData/Sources/SwoleData/UserExerciseConfig.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class UserExerciseConfig {
    public var exercise: Exercise?
    public var startingWeight: Double
    public var weightIncrement: Double
    public var setCount: Int
    public var repsPerSet: Int
    public var deloadThreshold: Int
    public var deloadPercentage: Double

    public init(
        exercise: Exercise?,
        startingWeight: Double,
        weightIncrement: Double,
        setCount: Int,
        repsPerSet: Int,
        deloadThreshold: Int,
        deloadPercentage: Double
    ) {
        self.exercise = exercise
        self.startingWeight = startingWeight
        self.weightIncrement = weightIncrement
        self.setCount = setCount
        self.repsPerSet = repsPerSet
        self.deloadThreshold = deloadThreshold
        self.deloadPercentage = deloadPercentage
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass (4 total so far)

- [ ] **Step 5: Commit**

```bash
cd /Users/josephbarbati/dev/project-swole
git add SwoleData/Sources/SwoleData/UserExerciseConfig.swift SwoleData/Tests/SwoleDataTests/UserExerciseConfigTests.swift
git commit -m "Add UserExerciseConfig model"
```

---

## Task 5: WorkoutTemplateExercise model (day assignment)

**Files:**
- Create: `SwoleData/Sources/SwoleData/WorkoutTemplateExercise.swift`
- Test: `SwoleData/Tests/SwoleDataTests/WorkoutTemplateExerciseTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SwoleData/Tests/SwoleDataTests/WorkoutTemplateExerciseTests.swift`:

```swift
import Testing
import SwiftData
@testable import SwoleData

@Test func sameExerciseCanAppearOnBothWorkoutDays() throws {
    let container = try ModelContainer(
        for: Exercise.self, WorkoutTemplateExercise.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    context.insert(WorkoutTemplateExercise(workoutType: .a, exercise: squat, order: 0))
    context.insert(WorkoutTemplateExercise(workoutType: .b, exercise: squat, order: 0))
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<WorkoutTemplateExercise>())
    #expect(fetched.count == 2)
    #expect(Set(fetched.map(\.workoutType)) == [.a, .b])
    #expect(fetched.allSatisfy { $0.exercise?.name == "Squat" })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter sameExerciseCanAppearOnBothWorkoutDays`
Expected: FAIL to build — `error: cannot find type 'WorkoutTemplateExercise' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `SwoleData/Sources/SwoleData/WorkoutTemplateExercise.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class WorkoutTemplateExercise {
    public var workoutType: WorkoutType
    public var exercise: Exercise?
    public var order: Int

    public init(workoutType: WorkoutType, exercise: Exercise?, order: Int) {
        self.workoutType = workoutType
        self.exercise = exercise
        self.order = order
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass (5 total so far)

- [ ] **Step 5: Commit**

```bash
cd /Users/josephbarbati/dev/project-swole
git add SwoleData/Sources/SwoleData/WorkoutTemplateExercise.swift SwoleData/Tests/SwoleDataTests/WorkoutTemplateExerciseTests.swift
git commit -m "Add WorkoutTemplateExercise model"
```

---

## Task 6: WorkoutSession, ExerciseLog, SetLog (session history + cascade delete)

**Files:**
- Create: `SwoleData/Sources/SwoleData/WorkoutSession.swift`
- Create: `SwoleData/Sources/SwoleData/ExerciseLog.swift`
- Create: `SwoleData/Sources/SwoleData/SetLog.swift`
- Test: `SwoleData/Tests/SwoleDataTests/ExerciseLogTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SwoleData/Tests/SwoleDataTests/ExerciseLogTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
@testable import SwoleData

@Test func succeededIsTrueOnlyWhenEverySetHitTargetReps() throws {
    let container = try ModelContainer(
        for: Exercise.self, WorkoutSession.self, ExerciseLog.self, SetLog.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    let session = WorkoutSession(date: Date(), workoutType: .a)
    context.insert(squat)
    context.insert(session)

    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 135, targetReps: 5)
    context.insert(log)
    for n in 1...5 {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: n == 5 ? 3 : 5))
    }
    try context.save()

    #expect(log.succeeded == false)

    log.sets.first { $0.setNumber == 5 }?.repsCompleted = 5
    try context.save()
    #expect(log.succeeded == true)
}

@Test func deletingSessionCascadesToLogsAndSets() throws {
    let container = try ModelContainer(
        for: Exercise.self, WorkoutSession.self, ExerciseLog.self, SetLog.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    let session = WorkoutSession(date: Date(), workoutType: .a)
    context.insert(squat)
    context.insert(session)
    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 135, targetReps: 5)
    context.insert(log)
    for n in 1...5 {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: 5))
    }
    try context.save()

    context.delete(session)
    try context.save()

    #expect(try context.fetch(FetchDescriptor<ExerciseLog>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<Exercise>()).count == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter succeededIsTrueOnlyWhenEverySetHitTargetReps`
Expected: FAIL to build — `error: cannot find type 'WorkoutSession' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `SwoleData/Sources/SwoleData/WorkoutSession.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class WorkoutSession {
    public var date: Date
    public var workoutType: WorkoutType
    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.session)
    public var exerciseLogs: [ExerciseLog] = []

    public init(date: Date, workoutType: WorkoutType) {
        self.date = date
        self.workoutType = workoutType
    }
}
```

Create `SwoleData/Sources/SwoleData/ExerciseLog.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class ExerciseLog {
    public var session: WorkoutSession?
    public var exercise: Exercise?
    public var targetWeight: Double
    public var targetReps: Int
    @Relationship(deleteRule: .cascade, inverse: \SetLog.exerciseLog)
    public var sets: [SetLog] = []

    public init(session: WorkoutSession?, exercise: Exercise?, targetWeight: Double, targetReps: Int) {
        self.session = session
        self.exercise = exercise
        self.targetWeight = targetWeight
        self.targetReps = targetReps
    }

    public var succeeded: Bool {
        !sets.isEmpty && sets.allSatisfy { $0.repsCompleted >= targetReps }
    }
}
```

Create `SwoleData/Sources/SwoleData/SetLog.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class SetLog {
    public var exerciseLog: ExerciseLog?
    public var setNumber: Int
    public var repsCompleted: Int

    public init(exerciseLog: ExerciseLog?, setNumber: Int, repsCompleted: Int) {
        self.exerciseLog = exerciseLog
        self.setNumber = setNumber
        self.repsCompleted = repsCompleted
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass (7 total so far)

- [ ] **Step 5: Commit**

```bash
cd /Users/josephbarbati/dev/project-swole
git add SwoleData/Sources/SwoleData/WorkoutSession.swift SwoleData/Sources/SwoleData/ExerciseLog.swift SwoleData/Sources/SwoleData/SetLog.swift SwoleData/Tests/SwoleDataTests/ExerciseLogTests.swift
git commit -m "Add WorkoutSession, ExerciseLog, SetLog models with cascade delete"
```

---

## Task 7: UserSettings model (singleton)

**Files:**
- Create: `SwoleData/Sources/SwoleData/UserSettings.swift`
- Test: `SwoleData/Tests/SwoleDataTests/UserSettingsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SwoleData/Tests/SwoleDataTests/UserSettingsTests.swift`:

```swift
import Testing
import SwiftData
@testable import SwoleData

@Test func userSettingsStoresUnitAndLastWorkoutType() throws {
    let container = try ModelContainer(
        for: UserSettings.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    let settings = UserSettings(unit: .lb, lastCompletedWorkoutType: nil)
    context.insert(settings)
    try context.save()

    settings.lastCompletedWorkoutType = .a
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<UserSettings>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.unit == .lb)
    #expect(fetched.first?.lastCompletedWorkoutType == .a)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter userSettingsStoresUnitAndLastWorkoutType`
Expected: FAIL to build — `error: cannot find type 'UserSettings' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `SwoleData/Sources/SwoleData/UserSettings.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class UserSettings {
    public var unit: MeasurementUnit
    public var lastCompletedWorkoutType: WorkoutType?

    public init(unit: MeasurementUnit, lastCompletedWorkoutType: WorkoutType?) {
        self.unit = unit
        self.lastCompletedWorkoutType = lastCompletedWorkoutType
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass (8 total so far)

- [ ] **Step 5: Commit**

```bash
cd /Users/josephbarbati/dev/project-swole
git add SwoleData/Sources/SwoleData/UserSettings.swift SwoleData/Tests/SwoleDataTests/UserSettingsTests.swift
git commit -m "Add UserSettings model"
```

---

## Task 8: Aggregate schema + shared test helper

**Files:**
- Create: `SwoleData/Sources/SwoleData/Schema.swift`
- Create: `SwoleData/Tests/SwoleDataTests/TestSupport.swift`
- Test: `SwoleData/Tests/SwoleDataTests/SchemaTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SwoleData/Tests/SwoleDataTests/TestSupport.swift`:

```swift
import SwiftData
@testable import SwoleData

func makeInMemoryContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: swoleSchema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}
```

Create `SwoleData/Tests/SwoleDataTests/SchemaTests.swift`:

```swift
import Testing
@testable import SwoleData

@Test func fullSchemaBuildsAnInMemoryContainer() throws {
    _ = try makeInMemoryContext()
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter fullSchemaBuildsAnInMemoryContainer`
Expected: FAIL to build — `error: cannot find 'swoleSchema' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `SwoleData/Sources/SwoleData/Schema.swift`:

```swift
import SwiftData

public let swoleSchema = Schema([
    Exercise.self,
    UserExerciseConfig.self,
    WorkoutTemplateExercise.self,
    WorkoutSession.self,
    ExerciseLog.self,
    SetLog.self,
    UserSettings.self,
])
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass (9 total so far)

- [ ] **Step 5: Commit**

```bash
cd /Users/josephbarbati/dev/project-swole
git add SwoleData/Sources/SwoleData/Schema.swift SwoleData/Tests/SwoleDataTests/TestSupport.swift SwoleData/Tests/SwoleDataTests/SchemaTests.swift
git commit -m "Add aggregate SwiftData schema and shared in-memory test helper"
```

---

## Task 9: StandardSeed (standard 5x5 setup)

**Files:**
- Create: `SwoleData/Sources/SwoleData/StandardSeed.swift`
- Test: `SwoleData/Tests/SwoleDataTests/StandardSeedTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SwoleData/Tests/SwoleDataTests/StandardSeedTests.swift`:

```swift
import Testing
import SwiftData
@testable import SwoleData

@Test func seedCreatesStandardFiveByFiveSetup() throws {
    let context = try makeInMemoryContext()

    let didSeed = try StandardSeed.seed(in: context)
    #expect(didSeed == true)

    let exercises = try context.fetch(FetchDescriptor<Exercise>())
    #expect(exercises.count == 5)
    #expect(Set(exercises.map(\.name)) == ["Squat", "Bench Press", "Overhead Press", "Deadlift", "Barbell Row"])

    let configs = try context.fetch(FetchDescriptor<UserExerciseConfig>())
    #expect(configs.count == 5)
    let deadliftConfig = configs.first { $0.exercise?.name == "Deadlift" }
    #expect(deadliftConfig?.weightIncrement == 10)
    #expect(deadliftConfig?.setCount == 1)
    let squatConfig = configs.first { $0.exercise?.name == "Squat" }
    #expect(squatConfig?.weightIncrement == 5)
    #expect(squatConfig?.setCount == 5)

    let templateEntries = try context.fetch(FetchDescriptor<WorkoutTemplateExercise>())
    #expect(templateEntries.count == 6)
    let dayA = templateEntries.filter { $0.workoutType == .a }
    #expect(Set(dayA.compactMap { $0.exercise?.name }) == ["Squat", "Bench Press", "Barbell Row"])
    let dayB = templateEntries.filter { $0.workoutType == .b }
    #expect(Set(dayB.compactMap { $0.exercise?.name }) == ["Squat", "Overhead Press", "Deadlift"])

    let settings = try context.fetch(FetchDescriptor<UserSettings>())
    #expect(settings.count == 1)
    #expect(settings.first?.unit == .lb)
    #expect(settings.first?.lastCompletedWorkoutType == nil)
}

@Test func seedDoesNotDuplicateOnSecondCall() throws {
    let context = try makeInMemoryContext()

    _ = try StandardSeed.seed(in: context)
    let didSeedAgain = try StandardSeed.seed(in: context)

    #expect(didSeedAgain == false)
    #expect(try context.fetch(FetchDescriptor<Exercise>()).count == 5)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter seedCreatesStandardFiveByFiveSetup`
Expected: FAIL to build — `error: cannot find 'StandardSeed' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `SwoleData/Sources/SwoleData/StandardSeed.swift`:

```swift
import Foundation
import SwiftData

public enum StandardSeed {
    @discardableResult
    public static func seed(in context: ModelContext) throws -> Bool {
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        guard existing.isEmpty else { return false }

        let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
        let bench = Exercise(name: "Bench Press", defaultSetCount: 5, defaultRepsPerSet: 5)
        let ohp = Exercise(name: "Overhead Press", defaultSetCount: 5, defaultRepsPerSet: 5)
        let deadlift = Exercise(name: "Deadlift", defaultSetCount: 1, defaultRepsPerSet: 5)
        let row = Exercise(name: "Barbell Row", defaultSetCount: 5, defaultRepsPerSet: 5)
        for exercise in [squat, bench, ohp, deadlift, row] {
            context.insert(exercise)
        }

        func makeConfig(_ exercise: Exercise, starting: Double, increment: Double) {
            context.insert(UserExerciseConfig(
                exercise: exercise,
                startingWeight: starting,
                weightIncrement: increment,
                setCount: exercise.defaultSetCount,
                repsPerSet: exercise.defaultRepsPerSet,
                deloadThreshold: 3,
                deloadPercentage: 0.10
            ))
        }
        makeConfig(squat, starting: 45, increment: 5)
        makeConfig(bench, starting: 45, increment: 5)
        makeConfig(ohp, starting: 45, increment: 5)
        makeConfig(deadlift, starting: 95, increment: 10)
        makeConfig(row, starting: 45, increment: 5)

        let templateEntries: [(WorkoutType, Exercise, Int)] = [
            (.a, squat, 0), (.a, bench, 1), (.a, row, 2),
            (.b, squat, 0), (.b, ohp, 1), (.b, deadlift, 2),
        ]
        for (type, exercise, order) in templateEntries {
            context.insert(WorkoutTemplateExercise(workoutType: type, exercise: exercise, order: order))
        }

        context.insert(UserSettings(unit: .lb, lastCompletedWorkoutType: nil))

        try context.save()
        return true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass (11 total so far)

- [ ] **Step 5: Commit**

```bash
cd /Users/josephbarbati/dev/project-swole
git add SwoleData/Sources/SwoleData/StandardSeed.swift SwoleData/Tests/SwoleDataTests/StandardSeedTests.swift
git commit -m "Add StandardSeed for standard 5x5 setup"
```

---

## Task 10: ProgressionCalculator (weight progression + deload)

**Files:**
- Create: `SwoleData/Sources/SwoleData/ProgressionCalculator.swift`
- Test: `SwoleData/Tests/SwoleDataTests/ProgressionCalculatorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SwoleData/Tests/SwoleDataTests/ProgressionCalculatorTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
@testable import SwoleData

@Test func nextTargetWeightWithNoHistoryUsesStartingWeight() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = UserExerciseConfig(
        exercise: squat, startingWeight: 45, weightIncrement: 5,
        setCount: 5, repsPerSet: 5, deloadThreshold: 3, deloadPercentage: 0.10
    )
    context.insert(config)
    try context.save()

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 45)
}

@Test func nextTargetWeightIncrementsAfterASuccessfulSession() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = UserExerciseConfig(
        exercise: squat, startingWeight: 45, weightIncrement: 5,
        setCount: 5, repsPerSet: 5, deloadThreshold: 3, deloadPercentage: 0.10
    )
    context.insert(config)
    let session = WorkoutSession(date: Date(), workoutType: .a)
    context.insert(session)
    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 135, targetReps: 5)
    context.insert(log)
    for n in 1...5 { context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: 5)) }
    try context.save()

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 140)
}

@Test func nextTargetWeightRepeatsAfterASingleFailure() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = UserExerciseConfig(
        exercise: squat, startingWeight: 45, weightIncrement: 5,
        setCount: 5, repsPerSet: 5, deloadThreshold: 3, deloadPercentage: 0.10
    )
    context.insert(config)
    let session = WorkoutSession(date: Date(), workoutType: .a)
    context.insert(session)
    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 200, targetReps: 5)
    context.insert(log)
    for n in 1...5 { context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: n == 5 ? 3 : 5)) }
    try context.save()

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 200)
}

@Test func nextTargetWeightDeloadsAfterThreeConsecutiveFailures() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = UserExerciseConfig(
        exercise: squat, startingWeight: 45, weightIncrement: 5,
        setCount: 5, repsPerSet: 5, deloadThreshold: 3, deloadPercentage: 0.10
    )
    context.insert(config)

    let calendar = Calendar.current
    for dayOffset in 0..<3 {
        let date = calendar.date(byAdding: .day, value: dayOffset, to: Date())!
        let session = WorkoutSession(date: date, workoutType: .a)
        context.insert(session)
        let log = ExerciseLog(session: session, exercise: squat, targetWeight: 200, targetReps: 5)
        context.insert(log)
        for n in 1...5 { context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: n == 5 ? 3 : 5)) }
    }
    try context.save()

    let streak = try ProgressionCalculator.currentFailStreak(for: squat, in: context)
    #expect(streak == 3)

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 180)
}

@Test func failStreakResetsAfterADeload() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let calendar = Calendar.current
    // 3 fails at 200 -> triggers a deload to 180. A 4th fail is then logged
    // AT the deloaded weight (180), simulating a real next session that used
    // ProgressionCalculator's own deloaded output as its target.
    let weights = [200.0, 200.0, 200.0, 180.0]
    for (dayOffset, weight) in weights.enumerated() {
        let date = calendar.date(byAdding: .day, value: dayOffset, to: Date())!
        let session = WorkoutSession(date: date, workoutType: .a)
        context.insert(session)
        let log = ExerciseLog(session: session, exercise: squat, targetWeight: weight, targetReps: 5)
        context.insert(log)
        for n in 1...5 { context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: n == 5 ? 3 : 5)) }
    }
    try context.save()

    // Streak should count only the single fail at the new (180) weight, not
    // all 4 fails across the deload boundary.
    let streak = try ProgressionCalculator.currentFailStreak(for: squat, in: context)
    #expect(streak == 1)

    let config = UserExerciseConfig(
        exercise: squat, startingWeight: 45, weightIncrement: 5,
        setCount: 5, repsPerSet: 5, deloadThreshold: 3, deloadPercentage: 0.10
    )
    context.insert(config)
    try context.save()

    // Below threshold again post-deload -> repeat at 180, not deload a second time to 162.
    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 180)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter nextTargetWeightWithNoHistoryUsesStartingWeight`
Expected: FAIL to build — `error: cannot find 'ProgressionCalculator' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `SwoleData/Sources/SwoleData/ProgressionCalculator.swift`:

```swift
import Foundation
import SwiftData

public enum ProgressionCalculator {
    private static func sortedLogs(for exercise: Exercise, in context: ModelContext) throws -> [ExerciseLog] {
        let exerciseID = exercise.persistentModelID
        let allLogs = try context.fetch(FetchDescriptor<ExerciseLog>())
        return allLogs
            .filter { $0.exercise?.persistentModelID == exerciseID }
            .sorted { ($0.session?.date ?? .distantPast) > ($1.session?.date ?? .distantPast) }
    }

    /// Counts consecutive fails back from the most recent log, stopping not
    /// just at the first success but also at any weight discontinuity: a
    /// fail-streak only repeats a session at the same weight (see
    /// `nextTargetWeight` below), so a change in `targetWeight` between two
    /// consecutive fails means a deload happened there, and the streak must
    /// not count fails from before that deload.
    public static func currentFailStreak(for exercise: Exercise, in context: ModelContext) throws -> Int {
        let logs = try sortedLogs(for: exercise, in: context)
        var streak = 0
        var streakWeight: Double?
        for log in logs {
            if log.succeeded { break }
            if let streakWeight, log.targetWeight != streakWeight { break }
            streak += 1
            streakWeight = log.targetWeight
        }
        return streak
    }

    public static func nextTargetWeight(
        for exercise: Exercise,
        config: UserExerciseConfig,
        in context: ModelContext
    ) throws -> Double {
        let logs = try sortedLogs(for: exercise, in: context)
        guard let lastLog = logs.first else {
            return config.startingWeight
        }
        if lastLog.succeeded {
            return lastLog.targetWeight + config.weightIncrement
        }
        let streak = try currentFailStreak(for: exercise, in: context)
        if streak >= config.deloadThreshold {
            return lastLog.targetWeight * (1 - config.deloadPercentage)
        }
        return lastLog.targetWeight
    }
}
```

Note: logs are fetched in full and filtered/sorted in memory rather than via a `#Predicate` on the relationship — SwiftData's predicate macro is unreliable across optional relationship chains, and at this app's scale (one local user, at most a few hundred logs) the in-memory approach is simpler and just as fast.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass (16 total so far)

- [ ] **Step 5: Commit**

```bash
cd /Users/josephbarbati/dev/project-swole
git add SwoleData/Sources/SwoleData/ProgressionCalculator.swift SwoleData/Tests/SwoleDataTests/ProgressionCalculatorTests.swift
git commit -m "Add ProgressionCalculator for weight progression and deload logic"
```

---

## Task 11: WorkoutScheduler (A/B alternation)

**Files:**
- Create: `SwoleData/Sources/SwoleData/WorkoutScheduler.swift`
- Test: `SwoleData/Tests/SwoleDataTests/WorkoutSchedulerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SwoleData/Tests/SwoleDataTests/WorkoutSchedulerTests.swift`:

```swift
import Testing
@testable import SwoleData

@Test func nextWorkoutTypeDefaultsToAWithNoHistory() {
    let settings = UserSettings(unit: .lb, lastCompletedWorkoutType: nil)
    #expect(WorkoutScheduler.nextWorkoutType(after: settings) == .a)
}

@Test func nextWorkoutTypeAlternatesFromA() {
    let settings = UserSettings(unit: .lb, lastCompletedWorkoutType: .a)
    #expect(WorkoutScheduler.nextWorkoutType(after: settings) == .b)
}

@Test func nextWorkoutTypeAlternatesFromB() {
    let settings = UserSettings(unit: .lb, lastCompletedWorkoutType: .b)
    #expect(WorkoutScheduler.nextWorkoutType(after: settings) == .a)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test --filter nextWorkoutTypeDefaultsToAWithNoHistory`
Expected: FAIL to build — `error: cannot find 'WorkoutScheduler' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `SwoleData/Sources/SwoleData/WorkoutScheduler.swift`:

```swift
public enum WorkoutScheduler {
    public static func nextWorkoutType(after settings: UserSettings) -> WorkoutType {
        switch settings.lastCompletedWorkoutType {
        case .none: return .a
        case .a: return .b
        case .b: return .a
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && swift test`
Expected: all tests pass (19 total)

- [ ] **Step 5: Commit**

```bash
cd /Users/josephbarbati/dev/project-swole
git add SwoleData/Sources/SwoleData/WorkoutScheduler.swift SwoleData/Tests/SwoleDataTests/WorkoutSchedulerTests.swift
git commit -m "Add WorkoutScheduler for A/B day alternation"
```

---

## Task 12: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite from a clean build**

Run:
```bash
cd /Users/josephbarbati/dev/project-swole/SwoleData
rm -rf .build
swift test
```
Expected: `Test run with 19 tests in 0 suites passed` and `swift build`/test both exit 0.

- [ ] **Step 2: Confirm the package's public API surface**

Run: `cd /Users/josephbarbati/dev/project-swole/SwoleData && grep -rn "^public" Sources/SwoleData | sort`
Expected: every model (`Exercise`, `UserExerciseConfig`, `WorkoutTemplateExercise`, `WorkoutSession`, `ExerciseLog`, `SetLog`, `UserSettings`), both enums (`WorkoutType`, `MeasurementUnit`), `swoleSchema`, `ProgressionCalculator`, `WorkoutScheduler`, and `StandardSeed` are listed — this is everything a future iOS app target needs to import and use.

- [ ] **Step 3: Commit if anything changed**

Only commit if Step 1 or 2 required a fix. If the suite already passed cleanly, no commit is needed here.

---

## What's Deliberately Not Built Here

- No Xcode `.xcodeproj`/App target yet — `SwoleData` is a plain library package. Adding the SwiftUI app that depends on it (via Xcode's "Add Local Package Dependency") is a separate, later plan.
- No warm-up set tracking, body weight tracking, or backend sync — out of scope per the design spec.
- No `userId` field on any model — single local user for now, per the design spec's stated migration path.
