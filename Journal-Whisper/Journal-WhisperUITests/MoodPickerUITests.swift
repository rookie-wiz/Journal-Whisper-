//
//  MoodPickerUITests.swift
//  Journal-WhisperUITests
//
//  Picks, changes and clears an entry's mood by hand (the non-AI path).
//

import XCTest

final class MoodPickerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockAI", "-seedActive", "1", "-seedDeleted", "0"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testPickChangeAndClearMood() throws {
        app.cells.firstMatch.tap()

        let chip = app.buttons["moodChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.label, "Add mood")

        // Pick a mood.
        chip.tap()
        let calm = app.buttons["mood.calm"]
        XCTAssertTrue(calm.waitForExistence(timeout: 5))
        calm.tap()
        XCTAssertTrue(app.segmentedControls["moodIntensity"].waitForExistence(timeout: 2))
        app.segmentedControls["moodIntensity"].buttons["5"].tap()
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.label, "Mood: Calm")

        // The list row shows the mood too.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Mood: Calm"].waitForExistence(timeout: 5))

        // Clear it again.
        app.cells.firstMatch.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        XCTAssertTrue(app.buttons["Clear"].waitForExistence(timeout: 5))
        app.buttons["Clear"].tap()
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.label, "Add mood")
    }
}
