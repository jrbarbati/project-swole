import XCTest

final class _x5iveUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Forces a fresh, seeded, in-memory SwiftData store per launch so
        // these tests don't accumulate state across runs.
        app.launchArguments = ["-uiTestingInMemoryStore"]
        app.launch()
        return app
    }

    private func setTile(in app: XCUIApplication, labeled label: String, value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND value == %@", label, value)
        ).firstMatch
    }

    // MARK: - Active workout flow

    @MainActor
    func testStartingWorkoutOpensActiveSessionWithFirstLiftExpanded() throws {
        let app = launchApp()

        let startButton = app.buttons["Start Workout A"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 5))
        // Squat is first in the A template and should auto-expand with its
        // set tiles visible and unlogged.
        let firstSet = app.descendants(matching: .any)["Set 1"]
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5))
        XCTAssertEqual(firstSet.value as? String, "not logged")
    }

    @MainActor
    func testTappingASetLogsRepsAndStartsRestTimer() throws {
        let app = launchApp()

        app.buttons["Start Workout A"].tap()
        let firstSet = app.descendants(matching: .any)["Set 1"]
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5))

        firstSet.tap()

        // The view model debounces for 1.5s before settling the tap and
        // starting rest, so poll past that window.
        let loggedSet = setTile(in: app, labeled: "Set 1", value: "5 reps")
        XCTAssertTrue(loggedSet.waitForExistence(timeout: 5))

        // RestBar's skip button renders through MetaLabel, which uppercases its text.
        XCTAssertTrue(app.buttons["SKIP"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCancelingWorkoutReturnsToTodayTab() throws {
        let app = launchApp()

        app.buttons["Start Workout A"].tap()
        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 5))

        app.buttons["Cancel"].tap()

        let alert = app.alerts["Cancel this workout?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete Workout"].tap()

        XCTAssertTrue(app.buttons["Start Workout A"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFinishingAWorkoutShowsTheXPRevealScreenWithTheEarnedTotal() throws {
        let app = launchApp()

        app.buttons["Start Workout A"].tap()
        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 5))

        app.buttons["Finish Workout"].tap()

        let alert = app.alerts["Some sets aren't logged"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Review & Finish"].tap()

        XCTAssertTrue(app.buttons["Complete Workout"].waitForExistence(timeout: 5))
        app.buttons["Complete Workout"].tap()

        // A fresh install starts at 0 XP; the workout's base 60 XP crosses the
        // level 1 threshold (50 XP), so this always shows the level-up variant.
        XCTAssertTrue(app.staticTexts["LEVEL UP!"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["+60"].waitForExistence(timeout: 5))

        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Start Workout B"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFinishingAWorkoutThatCrossesAVolumeMilestoneShowsTheNewBadgesRow() throws {
        let app = launchApp()

        app.buttons["Start Workout A"].tap()
        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 5))

        // Log every set of Squat (45 lb x 5 reps x 5 sets = 1125 lb) so it
        // crosses the smallest 1,000 lb per-exercise volume tier. Skip the
        // rest timer between sets so the test doesn't wait it out.
        for setNumber in 1...5 {
            let set = app.descendants(matching: .any)["Set \(setNumber)"]
            XCTAssertTrue(set.waitForExistence(timeout: 5))
            set.tap()
            if setNumber < 5 {
                XCTAssertTrue(app.buttons["SKIP"].waitForExistence(timeout: 5))
                app.buttons["SKIP"].tap()
            }
        }

        app.buttons["Finish Workout"].tap()

        let alert = app.alerts["Some sets aren't logged"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Review & Finish"].tap()

        XCTAssertTrue(app.buttons["Complete Workout"].waitForExistence(timeout: 5))
        app.buttons["Complete Workout"].tap()

        XCTAssertTrue(app.staticTexts["NEW BADGES"].waitForExistence(timeout: 5))

        app.buttons["Done"].tap()
    }

    // MARK: - Today view weight adjust

    @MainActor
    func testAdjustingWeightUpdatesDisplayAndDeltaLiveWithoutPersisting() throws {
        let app = launchApp()

        // Squat's un-adjusted plan: starting weight 45, no history yet, so delta reads HOLD.
        XCTAssertTrue(app.staticTexts["45"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HOLD"].waitForExistence(timeout: 5))

        app.buttons["weightIncrement-Squat"].tap()

        XCTAssertTrue(app.staticTexts["50"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["+5"].waitForExistence(timeout: 5))

        // Swapping the planned workout discards the pending adjustment.
        // One swap moves to Workout B; a second moves back to Workout A, where Squat lives.
        app.buttons["swapWorkoutButton"].tap()
        app.buttons["swapWorkoutButton"].tap()

        XCTAssertTrue(app.staticTexts["45"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HOLD"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStartingWorkoutBakesInTheAdjustedWeight() throws {
        let app = launchApp()

        app.buttons["weightIncrement-Squat"].tap()
        XCTAssertTrue(app.staticTexts["50"].waitForExistence(timeout: 5))

        app.buttons["Start Workout A"].tap()

        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["50"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStartingAWorkoutClearsThePendingAdjustmentAfterwards() throws {
        let app = launchApp()

        app.buttons["weightIncrement-Squat"].tap()
        XCTAssertTrue(app.staticTexts["50"].waitForExistence(timeout: 5))

        app.buttons["Start Workout A"].tap()
        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 5))

        app.buttons["Cancel"].tap()
        let alert = app.alerts["Cancel this workout?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete Workout"].tap()

        // The adjustment used to start that now-canceled workout must not
        // still be applied — Squat should show its plain computed weight
        // again, not the stale 50 from before.
        XCTAssertTrue(app.buttons["Start Workout A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["45"].waitForExistence(timeout: 5))
    }

    // MARK: - Manual past workout entry

    @MainActor
    func testLoggingAPastWorkoutAddsItToHistoryAndCanBeEdited() throws {
        let app = launchApp()

        app.buttons["HISTORY"].tap()

        let addButton = app.buttons["Log past workout"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.staticTexts["Log Past Workout"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()

        // Every exercise card is expanded at once here (unlike the active
        // workout screen), so several "Set 1" tiles exist simultaneously.
        let firstSet = app.descendants(matching: .any).matching(identifier: "Set 1").firstMatch
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5))
        firstSet.tap()
        let loggedSet = setTile(in: app, labeled: "Set 1", value: "5 reps")
        XCTAssertTrue(loggedSet.waitForExistence(timeout: 5))

        app.buttons["Complete Workout"].tap()

        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 5))

        app.buttons["Edit workout"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Edit Workout"].waitForExistence(timeout: 5))
        let editedSet = setTile(in: app, labeled: "Set 1", value: "5 reps")
        XCTAssertTrue(editedSet.waitForExistence(timeout: 5))
    }

    // MARK: - Bug repro: editing history should move the computed next weight

    @MainActor
    func testEditingTheMostRecentWorkoutsWeightUpdatesTheComputedNextWeight() throws {
        let app = launchApp()

        app.buttons["HISTORY"].tap()
        app.buttons["Log past workout"].tap()
        XCTAssertTrue(app.staticTexts["Log Past Workout"].waitForExistence(timeout: 5))
        app.buttons["Workout B"].tap()
        app.buttons["Continue"].tap()

        // Log all 5 Overhead Press sets to target reps — a clean success at
        // the seeded starting weight (45).
        for setNumber in 1...5 {
            let tile = app.descendants(matching: .any)["manualSet\(setNumber)-Overhead Press"]
            XCTAssertTrue(tile.waitForExistence(timeout: 5))
            tile.tap()
        }
        app.buttons["Complete Workout"].tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))

        // Baseline: one successful log at 45 should compute next weight as 50.
        app.buttons["SETTINGS"].tap()
        let weightLabel = app.staticTexts["settingsWeight-Overhead Press"]
        XCTAssertTrue(weightLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(weightLabel.label, "50")

        // Edit that same (most recent) workout's Overhead Press weight up to
        // 85, keeping every set at target reps (still a success).
        app.buttons["HISTORY"].tap()
        app.buttons["Edit workout"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Edit Workout"].waitForExistence(timeout: 5))
        let incrementButton = app.buttons["manualWeightIncrement-Overhead Press"]
        XCTAssertTrue(incrementButton.waitForExistence(timeout: 5))
        for _ in 0..<8 { incrementButton.tap() } // 45 -> 85 in +5 steps
        let editedWeightLabel = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label == %@", "manualWeight-Overhead Press", "85")
        ).firstMatch
        XCTAssertTrue(editedWeightLabel.waitForExistence(timeout: 5))
        app.buttons["Complete Workout"].tap()

        // The edited log is still the most recent — the computed next
        // weight should now be 90 (85 + 5), not the stale 50 from before.
        app.buttons["SETTINGS"].tap()
        XCTAssertTrue(weightLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(weightLabel.label, "90")
    }

    // MARK: - Bug repro: a stale manual weight nudge shadows history edits

    @MainActor
    func testLoggingAPastWorkoutAfterANudgeThenEditingItReflectsTheEditNotTheStaleNudge() throws {
        let app = launchApp()

        // Nudge Overhead Press up via Settings — this sets a one-shot
        // weightOverride that's normally consumed the next time a workout
        // is *started* live.
        app.buttons["SETTINGS"].tap()
        let settingsIncrement = app.buttons["settingsWeightIncrement-Overhead Press"]
        XCTAssertTrue(settingsIncrement.waitForExistence(timeout: 5))
        settingsIncrement.tap() // 45 -> 50
        let weightLabel = app.staticTexts["settingsWeight-Overhead Press"]
        XCTAssertEqual(weightLabel.label, "50")

        // Instead of starting a live workout, back-fill one via History —
        // this never consumed the override before this fix.
        app.buttons["HISTORY"].tap()
        app.buttons["Log past workout"].tap()
        XCTAssertTrue(app.staticTexts["Log Past Workout"].waitForExistence(timeout: 5))
        app.buttons["Workout B"].tap()
        app.buttons["Continue"].tap()
        for setNumber in 1...5 {
            app.descendants(matching: .any)["manualSet\(setNumber)-Overhead Press"].tap()
        }
        app.buttons["Complete Workout"].tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))

        // Now edit that same (most recent) workout's Overhead Press weight
        // up to 70, keeping it a success.
        app.buttons["Edit workout"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Edit Workout"].waitForExistence(timeout: 5))
        let editIncrement = app.buttons["manualWeightIncrement-Overhead Press"]
        XCTAssertTrue(editIncrement.waitForExistence(timeout: 5))
        for _ in 0..<4 { editIncrement.tap() } // 50 -> 70
        app.buttons["Complete Workout"].tap()

        // The edit should win: next weight is 75 (70 + 5), not the stale
        // 50 nudge from before the backfill.
        app.buttons["SETTINGS"].tap()
        XCTAssertTrue(weightLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(weightLabel.label, "75")
    }

    // MARK: - Delete data

    @MainActor
    func testDeletingDataResetsAppToFreshInstallState() throws {
        let app = launchApp()

        // Nudge a working weight so there's non-default state to wipe.
        app.buttons["SETTINGS"].tap()
        let incrementButton = app.buttons["settingsWeightIncrement-Squat"]
        XCTAssertTrue(incrementButton.waitForExistence(timeout: 5))
        incrementButton.tap()
        let weightLabel = app.staticTexts["settingsWeight-Squat"]
        XCTAssertEqual(weightLabel.label, "50")

        app.buttons["deleteDataButton"].tap()
        let confirmButton = app.buttons["Delete Everything"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        // Weight is back to the seeded default, not the pre-delete nudge.
        XCTAssertTrue(weightLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(weightLabel.label, "45")

        // Today tab is back to its never-used state.
        app.buttons["TODAY"].tap()
        XCTAssertTrue(app.buttons["Start Workout A"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDeletingDataWithFinishedWorkoutInHistoryDoesNotCrash() throws {
        let app = launchApp()

        app.buttons["HISTORY"].tap()
        app.buttons["Log past workout"].tap()
        XCTAssertTrue(app.staticTexts["Log Past Workout"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        let firstSet = app.descendants(matching: .any).matching(identifier: "Set 1").firstMatch
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5))
        firstSet.tap()
        let loggedSet = setTile(in: app, labeled: "Set 1", value: "5 reps")
        XCTAssertTrue(loggedSet.waitForExistence(timeout: 5))
        app.buttons["Complete Workout"].tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 5))

        app.buttons["SETTINGS"].tap()
        app.buttons["deleteDataButton"].tap()
        let confirmButton = app.buttons["Delete Everything"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        XCTAssertTrue(app.staticTexts["settingsWeight-Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.exists)
    }

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
        // "Workout A" text also renders inside the mini bar itself, so it
        // can't be used to prove the full-screen ActiveWorkoutView was
        // dismissed. minimizeWorkoutButton only exists in that full screen,
        // so its absence is the real signal minimizing worked.
        XCTAssertFalse(app.buttons["minimizeWorkoutButton"].exists)

        let countdown = app.staticTexts["activeWorkoutBarRestCountdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))
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

    // MARK: - Live Activity content state (regression)

    /// Clearing a set logs `repsCompleted == nil` without starting or ending
    /// a rest, reaching `currentActivityState()` only through the
    /// `.onChange(of: session.loggedSetCount)` trigger. Can't observe the
    /// Live Activity itself, but exercises that code path.
    @MainActor
    func testClearingALoggedSetViaTheRepPickerKeepsTheWorkoutResponsive() throws {
        let app = launchApp()

        app.buttons["Start Workout A"].tap()
        let firstSet = app.descendants(matching: .any)["Set 1"]
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5))
        firstSet.tap()

        let loggedSet = setTile(in: app, labeled: "Set 1", value: "5 reps")
        XCTAssertTrue(loggedSet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["SKIP"].waitForExistence(timeout: 5))
        app.buttons["SKIP"].tap()

        // XCUITest's synthetic touch needs more than SetTileRow's 0.35s minimum to register as a long press.
        loggedSet.press(forDuration: 1.2)
        XCTAssertTrue(app.staticTexts["How many reps?"].waitForExistence(timeout: 5))
        app.buttons["Clear set"].tap()

        let clearedSet = setTile(in: app, labeled: "Set 1", value: "not logged")
        XCTAssertTrue(clearedSet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Workout A"].exists)
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
}
