//
//  OnboardingUITests.swift
//  Journal-WhisperUITests
//
//  First-run onboarding, and the first badge celebration.
//

import XCTest

final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testThreePagesThenJournal() throws {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockAI", "-showOnboarding", "-seedActive", "0", "-seedDeleted", "0"]
        app.launch()

        let next = app.buttons["onboardingNext"]
        XCTAssertTrue(app.staticTexts["Your pages stay with you"].waitForExistence(timeout: 10))
        screenshot("Onboarding 1")
        next.tap()
        XCTAssertTrue(app.staticTexts["A gentle helper, on your iPhone"].waitForExistence(timeout: 5))
        screenshot("Onboarding 2")
        next.tap()
        XCTAssertTrue(app.staticTexts["Your lantern grows with you"].waitForExistence(timeout: 5))
        XCTAssertEqual(next.label, "Let's go")
        screenshot("Onboarding 3")
        next.tap()

        // Lock screen asks to unlock (skipped in UI tests), then the journal.
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testSkip() throws {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockAI", "-showOnboarding", "-seedActive", "0", "-seedDeleted", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["onboardingSkip"].waitForExistence(timeout: 10))
        app.buttons["onboardingSkip"].tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testFirstBadgeIsCelebratedAndShownInInsights() throws {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockAI", "-seedActive", "0", "-seedDeleted", "0"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))

        app.buttons["New Entry"].firstMatch.tap()
        let text = app.descendants(matching: .any)["entryText"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.typeText("First page in my new journal.")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let toast = app.descendants(matching: .any)["badgeToast"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(toast.label.contains("First page") && toast.label.contains("Wrote your first entry"), toast.label)
        screenshot("Badge toast")

        app.buttons["Insights"].tap()
        let badge = app.descendants(matching: .any)["badge-firstEntry"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertTrue((badge.value as? String ?? "").hasPrefix("Earned"))
        XCTAssertTrue((app.descendants(matching: .any)["badge-sevenDays"].firstMatch.value as? String ?? "").hasPrefix("Not yet"))
        screenshot("Insights companion")
    }
}
