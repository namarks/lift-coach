import XCTest

final class CoachingContextJourneyTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testAuthoredContextAndRecentFeedbackRetainRecordedSetSemantics() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CoachingContext", withExtension: "json"))
        let app = XCUIApplication()
        app.launchEnvironment["TRESFORT_UI_FIXTURE"] = "plan-changes"
        app.launchEnvironment["TRESFORT_UI_COACHING_CONTRACT"] = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Workout options"].waitForExistence(timeout: 15))
        app.buttons["Workout options"].tap()
        app.buttons["Coaching context"].tap()
        XCTAssertTrue(app.navigationBars["Coaching context"].waitForExistence(timeout: 10))
        app.buttons["coaching.session.recent"].tap()
        let hold = app.staticTexts["Plank: 45s · bodyweight"]
        for _ in 0..<4 where !hold.isHittable { app.swipeUp() }
        XCTAssertTrue(hold.exists)
        XCTAssertTrue(app.staticTexts["Pull-Up: 8 reps · 30 lb assistance · RPE 7"].exists)
        XCTAssertTrue(app.staticTexts["Split Squat: 8 reps per side · 22.25 lb each hand · RPE 8.5"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "coaching-session-semantics"; screenshot.lifetime = .keepAlways; add(screenshot)
        for _ in 0..<5 where !app.buttons["coaching.plan"].isHittable { app.swipeDown() }
        app.buttons["coaching.plan"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Autumn event'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Hotel gym only'")).firstMatch.exists)
        let plan = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        plan.name = "coaching-authored-context"; plan.lifetime = .keepAlways; add(plan)
    }
}
