//
//  InsightsUITests.swift
//  Journal-WhisperUITests
//
//  The Insights screen against DebugSeed's fixed week (-seedWeek): today and
//  the two days before, a gap, then five consecutive days.
//

import XCTest

final class InsightsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockAI", "-seedActive", "0", "-seedDeleted", "0", "-seedWeek"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
        app.buttons["Insights"].tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testJournalAndEditorScreens() throws {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockAI", "-seedActive", "0", "-seedDeleted", "0", "-seedWeek"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
        sleep(4)   // let the badge celebration pass
        screenshot("Journal list")
        app.cells.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["moodChip"].waitForExistence(timeout: 5))
        screenshot("Editor")
    }

    @MainActor
    func testStreakAndWeek() throws {
        launch()
        XCTAssertEqual(app.staticTexts["currentStreak"].label, "3 days")
        XCTAssertEqual(app.staticTexts["longestStreak"].label, "5 days")
        XCTAssertTrue(app.descendants(matching: .any)["weekMoodStrip"].exists)
        XCTAssertEqual(app.staticTexts["periodTitle"].label, "This week")
        XCTAssertFalse(app.buttons["nextPeriod"].isEnabled, "Can't go past the current week")
        XCTAssertTrue(app.descendants(matching: .any)["moodFrequencyChart"].exists)
        screenshot("Insights week")
    }

    @MainActor
    func testWeeklySummaryCard() throws {
        launch()
        let text = app.staticTexts["summaryText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        // -mockAI: MockSummaryEngine's fixed text.
        XCTAssertEqual(text.label, "This week you made time to write, and calm moments sat alongside some worry.")
        XCTAssertTrue(app.staticTexts["summaryQuestion"].exists)
        let footer = app.staticTexts["summaryFooter"].label
        XCTAssertTrue(footer.hasPrefix("Based on"), footer)
        XCTAssertFalse(footer.contains("moods"), "A written summary needs no explanation: \(footer)")
        screenshot("Weekly summary")

        // Only weeks get a summary.
        app.segmentedControls["insightsSpan"].buttons["Month"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["weeklySummaryCard"].exists)
    }

    @MainActor
    func testDeclinedSummaryFallsBackCalmly() throws {
        launch(["-mockAIFailure"])
        let text = app.staticTexts["summaryText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(text.label.hasPrefix("You wrote"), "Offline template: \(text.label)")
        let footer = app.staticTexts["summaryFooter"].label
        XCTAssertTrue(footer.contains("wasn't available for this week"), footer)
        screenshot("Weekly summary declined")
    }

    @MainActor
    func testMonthChartAndNavigation() throws {
        launch()
        app.segmentedControls["insightsSpan"].buttons["Month"].tap()
        XCTAssertEqual(app.staticTexts["periodTitle"].label, "This month")
        XCTAssertTrue(app.descendants(matching: .any)["moodMonthChart"].waitForExistence(timeout: 5)
                      || app.staticTexts["No entries this month."].exists)
        screenshot("Insights month")

        // Back one week, then forward again.
        app.segmentedControls["insightsSpan"].buttons["Week"].tap()
        app.buttons["previousPeriod"].tap()
        XCTAssertNotEqual(app.staticTexts["periodTitle"].label, "This week")
        XCTAssertTrue(app.buttons["nextPeriod"].isEnabled)
        app.buttons["nextPeriod"].tap()
        XCTAssertEqual(app.staticTexts["periodTitle"].label, "This week")
    }

    @MainActor
    func testEmptyJournal() throws {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockAI", "-seedActive", "0", "-seedDeleted", "0"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
        app.buttons["Insights"].tap()
        XCTAssertEqual(app.staticTexts["currentStreak"].label, "0 days")
        XCTAssertTrue(app.staticTexts["Write today to start a new streak."].exists)
        XCTAssertTrue(app.staticTexts["No entries this week."].exists)
        XCTAssertTrue(app.staticTexts["Write this week to see a summary here."].exists)
        screenshot("Insights empty")
    }
}
