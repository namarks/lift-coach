import XCTest

final class TrainingJourneyTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @discardableResult
    private func launch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRESFORT_UI_FIXTURE"] = fixture
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["fixture.scenario"].waitForExistence(timeout: 10))
        return app
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFreshSignInShowsExplicitAppleEntry() {
        let app = launch("sign-in")
        // Fixture mode substitutes only the provider button: exercise sign-in
        // intent without launching AuthenticationServices or sending credentials.
        XCTAssertTrue(app.buttons["Sign in with Apple"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Build a routine"].exists)
        screenshot("fresh-sign-in")
        app.buttons["Sign in with Apple"].tap()
        XCTAssertTrue(app.staticTexts["Sign-in requested (synthetic)"].waitForExistence(timeout: 5))
    }

    func testVerifiedEmptyPlanCanCreateRoutineAndFirstWorkout() {
        let app = launch("empty")
        XCTAssertTrue(app.buttons["Build a routine"].waitForExistence(timeout: 10))
        screenshot("verified-empty-plan")
        app.buttons["Build a routine"].tap()
        app.buttons["Create routine"].tap()
        XCTAssertTrue(app.staticTexts["Workout A"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Create routine"].exists)
        screenshot("created-first-workout")
    }

    func testFailedInitialLoadCannotMasqueradeAsEmptyPlan() {
        let app = launch("load-failure")
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Build a routine"].exists)
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.staticTexts["COULDN’T LOAD YOUR PLAN"].waitForExistence(timeout: 5))
        screenshot("failed-initial-load")
    }

    func testOrdinarySetLogsAndCompletesThroughAcknowledgement() {
        let app = launch("ordinary")
        XCTAssertTrue(app.buttons["LOG SET 1"].waitForExistence(timeout: 10))
        screenshot("ordinary-workout")
        app.buttons["LOG SET 1"].tap()
        XCTAssertTrue(app.buttons["DONE"].waitForExistence(timeout: 5))
        app.buttons["DONE"].tap()
        XCTAssertTrue(app.staticTexts["READY TO FINISH"].waitForExistence(timeout: 10))
        screenshot("logged-ready-to-finish")
        let finish = app.buttons["FINISH"]
        if !finish.isHittable { app.swipeUp() }
        finish.tap()
        XCTAssertTrue(app.staticTexts["WORKOUT COMPLETE"].waitForExistence(timeout: 10))
        screenshot("acknowledged-completion")
    }

    func testBodyweightAndTimedRunnerFixtures() {
        let bodyweight = launch("bodyweight")
        XCTAssertTrue(bodyweight.buttons["LOG SET 1"].waitForExistence(timeout: 10))
        screenshot("bodyweight-workout")
        bodyweight.terminate()
        let timed = launch("timed")
        XCTAssertTrue(timed.staticTexts["PLANK"].waitForExistence(timeout: 10))
        screenshot("timed-workout")
    }

    func testPendingSetRemainsVisibleUntilAcknowledged() {
        let app = launch("pending")
        XCTAssertTrue(app.staticTexts["Set queued on this device"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sets queued on this device"].exists)
        XCTAssertFalse(app.staticTexts["WORKOUT COMPLETE"].exists)
        screenshot("pending-write")
    }

    func testCorrectionFailurePreservesOriginalAndOffersRecovery() {
        let app = launch("correction-failure")
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 10))
        app.buttons["Edit"].tap()
        let reps = app.textFields["Reps"]
        XCTAssertTrue(reps.waitForExistence(timeout: 5))
        reps.doubleTap()
        reps.typeText("6")
        XCTAssertEqual(reps.value as? String, "6")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Edit rejected (HTTP 422)."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["45 × 5"].exists)
        screenshot("correction-failure-original-retained")
    }

    func testReadyToFinishFixtureRequiresExplicitFinish() {
        let app = launch("ready-to-finish")
        XCTAssertTrue(app.staticTexts["READY TO FINISH"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["FINISH"].exists)
        XCTAssertFalse(app.staticTexts["WORKOUT COMPLETE"].exists)
        screenshot("ready-to-finish")
    }
}
