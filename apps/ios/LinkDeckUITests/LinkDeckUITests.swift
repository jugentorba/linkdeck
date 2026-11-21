import XCTest

final class LinkDeckUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testAddOpenHomeScreenAndRemove() throws {
        XCTAssertTrue(
            app.staticTexts["Nothing here yet"].waitForExistence(timeout: 15),
            "Deck should start empty"
        )

        // Settings opens and both blocking toggles are present.
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["blockAdsToggle"].exists)
        XCTAssertTrue(app.switches["blockPopupsToggle"].exists)
        app.buttons["closeSettings"].tap()

        // Add sheet: invalid input stays inline, then a valid URL is accepted.
        app.buttons["addLinkButton"].tap()
        XCTAssertTrue(app.staticTexts["Add a link"].waitForExistence(timeout: 5))

        let urlField = app.textFields["urlField"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))
        urlField.tap()
        urlField.typeText("not a url")
        app.buttons["addToDeckButton"].tap()
        XCTAssertTrue(
            app.staticTexts["That doesn't look like a web address. Try example.com."].waitForExistence(timeout: 3)
        )

        urlField.tap()
        urlField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        urlField.typeText("wikipedia.org")

        let nameField = app.textFields["nameField"]
        XCTAssertEqual(nameField.value as? String, "Wikipedia")

        app.buttons["addToDeckButton"].tap()

        let tile = app.buttons["deckTile"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Wikipedia"].exists)

        // Open the app-like browser.
        tile.tap()
        let menu = app.buttons["browserMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "Browser header should appear")

        // The Home Screen sheet is honest and offers the two documented actions.
        menu.tap()
        XCTAssertTrue(app.buttons["Add to Home Screen"].waitForExistence(timeout: 5))
        app.buttons["Add to Home Screen"].tap()
        XCTAssertTrue(app.buttons["Open in Safari"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Copy link"].exists)
        app.buttons["closeHomeSheet"].tap()

        // Remove returns to an empty deck.
        let refreshedMenu = app.buttons["browserMenu"]
        XCTAssertTrue(refreshedMenu.waitForExistence(timeout: 5))
        refreshedMenu.tap()
        app.buttons["Remove from deck"].tap()
        let confirm = app.buttons["Remove"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(app.staticTexts["Nothing here yet"].waitForExistence(timeout: 10))
    }
}
