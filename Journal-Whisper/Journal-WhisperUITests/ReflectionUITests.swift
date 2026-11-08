//
//  ReflectionUITests.swift
//  Journal-WhisperUITests
//
//  Prompts, mood suggestions, the support card and the offline fallback,
//  driven through the real UI with MockReflectionEngine standing in for the
//  model (-mockAI), so results are fast and identical on every machine.
//

import XCTest

final class ReflectionUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Over the 20-word minimum for automatic mood tagging.
    private let longEntry = "Spent the afternoon at the library and then walked home the long way. "
        + "The streets were quiet and I had time to think about the week and what comes next."

    /// Mirrors MockReflectionEngine.prompts.
    private let mockPrompts = [
        "What felt most important about today?",
        "Where did you notice a change in how you felt?",
        "What would you like to carry into tomorrow?",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = ["-mockAI"]) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedActive", "0", "-seedDeleted", "0"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
    }

    /// Opens a new entry and returns its text field (keyboard already up).
    private func newEntry() -> XCUIElement {
        app.buttons["New Entry"].firstMatch.tap()
        let text = app.descendants(matching: .any)["entryText"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        return text
    }

    private var promptButtons: [XCUIElement] {
        app.buttons.matching(identifier: "reflectionPrompt").allElementsBoundByIndex
    }

    @MainActor
    func testPromptsAppearAndInsertIntoEntry() throws {
        launch()
        let text = newEntry()
        text.typeText("Long day.")

        app.buttons["reflectButton"].tap()
        XCTAssertTrue(app.buttons["reflectionPrompt"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(promptButtons.map(\.label), mockPrompts)

        app.buttons[mockPrompts[0]].tap()
        XCTAssertFalse(app.buttons["reflectionPrompt"].exists, "Prompts should close after choosing one")
        XCTAssertTrue((text.value as? String ?? "").contains(mockPrompts[0]))
    }

    @MainActor
    func testClosingPrompts() throws {
        launch()
        _ = newEntry()
        app.buttons["reflectButton"].tap()
        XCTAssertTrue(app.buttons["reflectionPrompt"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Close Prompts"].tap()
        XCTAssertFalse(app.buttons["reflectionPrompt"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testMoodIsSuggestedAndUserCanOverride() throws {
        launch()
        let text = newEntry()
        text.typeText(longEntry)

        // The suggestion lands after the 3s pause.
        let chip = app.buttons["moodChip"]
        expectation(for: NSPredicate(format: "label == 'Mood: Calm, suggested'"), evaluatedWith: chip)
        waitForExpectations(timeout: 10)

        // Choosing a mood replaces the suggestion and removes the "suggested" mark.
        app.buttons["Done"].firstMatch.tap()
        chip.tap()
        XCTAssertTrue(app.buttons["mood.content"].waitForExistence(timeout: 5))
        app.buttons["mood.content"].tap()
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.label, "Mood: Content")

        // Further edits never overwrite the user's choice.
        text.tap()
        text.typeText(" Then dinner with friends.")
        sleep(5)
        XCTAssertEqual(chip.label, "Mood: Content")
    }

    @MainActor
    func testShortEntryIsNotTaggedOnClose() throws {
        launch()
        let text = newEntry()
        text.typeText("Quick note.")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.cells.firstMatch.tap()
        XCTAssertEqual(app.buttons["moodChip"].label, "Add mood")
    }

    @MainActor
    func testCrisisWordingShowsSupportCard() throws {
        launch()
        let text = newEntry()
        text.typeText("Some days I want to die.")

        XCTAssertTrue(app.descendants(matching: .any)["supportCard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reflectButton"].exists)

        // Mood is never tagged for a crisis entry, even after the pause.
        sleep(5)
        XCTAssertEqual(app.buttons["moodChip"].label, "Add mood")

        // Removing the wording brings the normal controls back.
        text.tap()
        text.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) {
            app.menuItems["Select All"].tap()
        }
        text.typeText(XCUIKeyboardKey.delete.rawValue)
        text.typeText("Better today.")
        XCTAssertTrue(app.buttons["reflectButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["supportCard"].exists)
    }

    @MainActor
    func testModelFailureFallsBackToOfflinePrompts() throws {
        launch(["-mockAIFailure"])
        let text = newEntry()
        text.typeText("Long day.")

        app.buttons["reflectButton"].tap()
        XCTAssertTrue(app.buttons["reflectionPrompt"].firstMatch.waitForExistence(timeout: 5))
        let labels = promptButtons.map(\.label)
        XCTAssertEqual(labels.count, 3)
        XCTAssertTrue(Set(labels).isDisjoint(with: mockPrompts), "Expected prompt-bank prompts, got \(labels)")
    }
}
