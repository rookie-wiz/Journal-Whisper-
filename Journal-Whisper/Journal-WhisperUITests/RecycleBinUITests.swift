//
//  RecycleBinUITests.swift
//  Journal-WhisperUITests
//
//  Exercises swipe-to-delete, Recently Deleted, restore, permanent delete and
//  empty-bin against an in-memory store seeded by DebugSeed.
//

import XCTest

final class RecycleBinUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(active: Int, deleted: Int) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockAI", "-logToFile",
                               "-seedActive", "\(active)", "-seedDeleted", "\(deleted)"]
        app.launch()
        // Simulator has no passcode, so the app unlocks itself.
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
    }

    private func openRecycleBin() {
        let direct = app.buttons["Recently Deleted"]
        if !direct.exists {
            // .secondaryAction items live in the overflow menu.
            app.navigationBars["Journal"].buttons.element(boundBy: app.navigationBars["Journal"].buttons.count - 1).tap()
        }
        XCTAssertTrue(app.buttons["Recently Deleted"].waitForExistence(timeout: 5))
        app.buttons["Recently Deleted"].tap()
        XCTAssertTrue(app.navigationBars["Recently Deleted"].waitForExistence(timeout: 5))
    }

    private func timed(_ label: String, _ block: () -> Void) {
        let start = Date()
        block()
        print(String(format: "⏱ %@: %.2fs", label, Date().timeIntervalSince(start)))
    }

    @MainActor
    func testRecycleBinFlow() throws {
        launch(active: 50, deleted: 300)

        // Swipe left on a journal entry → confirmation → moved to bin.
        let first = app.cells.firstMatch
        let firstLabel = first.staticTexts.firstMatch.label
        timed("swipe-delete journal entry") {
            first.swipeLeft()
            XCTAssertTrue(app.buttons["Delete"].firstMatch.waitForExistence(timeout: 3))
            app.buttons["Delete"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Move to Recently Deleted"].waitForExistence(timeout: 5))
            app.buttons["Move to Recently Deleted"].tap()
            XCTAssertFalse(app.staticTexts[firstLabel].waitForExistence(timeout: 1))
        }

        timed("open bin (301 entries)") { openRecycleBin() }
        XCTAssertTrue(app.staticTexts[firstLabel].exists, "Deleted entry should appear in the bin")

        timed("scroll bin") {
            for _ in 0..<6 { app.swipeUp(velocity: .fast) }
            for _ in 0..<6 { app.swipeDown(velocity: .fast) }
        }

        // Restore (swipe right).
        let binRow = app.cells.containing(.staticText, identifier: firstLabel).firstMatch
        timed("restore") {
            binRow.swipeRight()
            app.buttons["Restore"].firstMatch.tap()
            XCTAssertFalse(app.staticTexts[firstLabel].waitForExistence(timeout: 1))
        }

        // Permanent delete of one entry (auth auto-passes with no passcode).
        let victim = app.cells.firstMatch
        let victimLabel = victim.staticTexts.firstMatch.label
        timed("permanent delete one") {
            victim.swipeLeft()
            XCTAssertTrue(app.buttons["Delete"].firstMatch.waitForExistence(timeout: 3))
            app.buttons["Delete"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Delete Permanently"].waitForExistence(timeout: 5))
            app.buttons["Delete Permanently"].tap()
            let gone = NSPredicate(format: "exists == false")
            expectation(for: gone, evaluatedWith: app.staticTexts[victimLabel])
            waitForExpectations(timeout: 5)
        }

        // Empty the bin.
        timed("empty bin (299 entries)") {
            app.buttons["Empty"].tap()
            XCTAssertTrue(app.buttons["Delete All"].waitForExistence(timeout: 5))
            app.buttons["Delete All"].tap()
            XCTAssertTrue(app.staticTexts["No Recently Deleted Entries"].waitForExistence(timeout: 15))
        }

        // Back to the journal: restored entry is there.
        timed("back to journal") {
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.staticTexts[firstLabel].exists, "Restored entry should be back in the journal")
    }
}
