import XCTest

final class PlanChangeJourneyTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDismissRelaunchRevisitBothActorsAndRestore() {
        let app = XCUIApplication()
        app.launchEnvironment["TRESFORT_UI_FIXTURE"] = "plan-changes"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["planChanges.review"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Prefer five reps' AND label CONTAINS 'You' AND label CONTAINS 'Barbell Squat'")).firstMatch.exists)
        app.buttons["planChanges.dismiss"].tap()
        XCTAssertFalse(app.buttons["planChanges.review"].exists)
        app.terminate()
        app.launchEnvironment["TRESFORT_UI_REUSE_PLAN_CHANGES"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Workout options"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["planChanges.review"].exists)
        app.buttons["Workout options"].tap()
        app.buttons["Workout history"].tap()
        XCTAssertTrue(app.buttons["planHistory.before.3"].waitForExistence(timeout: 10))
        let coach = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Reduced load after your feedback' AND label CONTAINS 'Coach'"))
        for _ in 0..<4 where !app.buttons["planHistory.before.2"].isHittable { app.swipeUp() }
        XCTAssertTrue(coach.firstMatch.exists)
        let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        before.name = "plan-changes-both-authors"; before.lifetime = .keepAlways; add(before)
        app.buttons["planHistory.before.2"].tap()
        let restore = app.buttons["Restore version 1"]
        for _ in 0..<4 where !restore.isHittable { app.swipeDown() }
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["65 lb → 45 lb"].exists)
        restore.tap()
        app.buttons["Restore as a new version"].tap()
        XCTAssertTrue(app.buttons["planHistory.before.4"].waitForExistence(timeout: 10))
        app.navigationBars["Workout history"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["planChanges.review"].waitForExistence(timeout: 10))
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        after.name = "plan-change-restore-visible"; after.lifetime = .keepAlways; add(after)
    }

    func testRecentChangeReachesExistingWorkoutCorrectionControls() {
        let app = XCUIApplication()
        app.launchEnvironment["TRESFORT_UI_FIXTURE"] = "plan-changes"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["planChanges.review"].waitForExistence(timeout: 15))
        app.buttons["planChanges.review"].tap()
        XCTAssertTrue(app.buttons["planHistory.correct"].waitForExistence(timeout: 10))
        app.buttons["planHistory.correct"].tap()
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Workout A'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Workout actions"].waitForExistence(timeout: 5))
        app.buttons["Workout actions"].tap()
        XCTAssertTrue(app.buttons["Add exercise"].waitForExistence(timeout: 5))
    }
}
