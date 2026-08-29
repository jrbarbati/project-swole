//
//  _x5iveUITests.swift
//  5x5iveUITests
//
//  Created by Joseph Barbati on 8/27/26.
//

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

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
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
        let loggedSet = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND value == %@", "Set 1", "5 reps")
        ).firstMatch
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

        // Back on Today: the adjustment used to start that (now-canceled)
        // workout must not still be applied — Squat should show its plain
        // computed weight again, not the stale 50 from before.
        XCTAssertTrue(app.buttons["Start Workout A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["45"].waitForExistence(timeout: 5))
    }
}
