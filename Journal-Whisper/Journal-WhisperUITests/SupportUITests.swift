//
//  SupportUITests.swift
//  Journal-WhisperUITests
//
//  The crisis-resources screen, from the journal menu and from the support card.
//

import XCTest

final class SupportUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-mockAI", "-seedActive", "0", "-seedDeleted", "0"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// `.secondaryAction` items live in the overflow menu.
    private func openMenuItem(_ title: String) {
        if !app.buttons[title].exists {
            let bar = app.navigationBars["Journal"]
            bar.buttons.element(boundBy: bar.buttons.count - 1).tap()
        }
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5))
        app.buttons[title].tap()
    }

    @MainActor
    func testGetSupportFromMenu() throws {
        openMenuItem("Get Support")
        XCTAssertTrue(app.navigationBars["Get Support"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You're not alone"].waitForExistence(timeout: 5))
        // SwiftUI Links appear as links, not buttons: look them up by identifier.
        XCTAssertTrue(element("findAHelpline").waitForExistence(timeout: 5))

        // Pick India explicitly (the simulator's region may differ).
        app.buttons["chooseRegion"].tap()
        let india = app.buttons[Locale.current.localizedString(forRegionCode: "IN") ?? "India"]
        XCTAssertTrue(india.waitForExistence(timeout: 5))
        india.tap()
        XCTAssertTrue(element("call-14416").waitForExistence(timeout: 5))
        XCTAssertTrue(element("callEmergency").label.contains("112"), element("callEmergency").label)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Get Support"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testGetSupportFromSupportCard() throws {
        app.buttons["New Entry"].firstMatch.tap()
        let text = app.descendants(matching: .any)["entryText"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.typeText("Some days I want to die.")

        let button = app.buttons["getSupportNow"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.staticTexts["You're not alone"].waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["getSupportNow"].waitForExistence(timeout: 5), "Back in the editor")
    }
    @MainActor
    func testAboutPrivacyAndDeleteEverything() throws {
        // Relaunch with entries to delete.
        app.terminate()
        app.launchArguments = ["-uiTesting", "-mockAI", "-seedActive", "3", "-seedDeleted", "2", "-seedWeek"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.cells.count > 0)

        openMenuItem("About & Privacy")
        XCTAssertTrue(app.navigationBars["About & Privacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("aiStatus").exists)

        element("privacyPolicyLink").tap()
        XCTAssertTrue(app.staticTexts["Not a medical or crisis service"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        element("deleteAllData").tap()
        XCTAssertTrue(app.buttons["Delete Everything"].waitForExistence(timeout: 5))
        app.buttons["Delete Everything"].tap()
        XCTAssertTrue(app.staticTexts["All journal data has been deleted."].waitForExistence(timeout: 5))

        // Back on the journal: nothing left, including Recently Deleted.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["No Entries Yet"].waitForExistence(timeout: 5))
        openMenuItem("Recently Deleted")
        XCTAssertTrue(app.staticTexts["No Recently Deleted Entries"].waitForExistence(timeout: 5))
    }
}
