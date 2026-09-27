import XCTest

/// Walks the main iOS surfaces with demo data and attaches a screenshot of each.
/// Uses an in-memory store, so it never touches real clips.
final class ClipbaraiOSUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ClipbaraDemoData"]
        app.launch()
        dismissSystemAlerts()
    }

    func testMainSurfaces() throws {
        let cards = app.descendants(matching: .any).matching(identifier: "clipCard")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        attach("01-history")

        // Tap copies and shows a toast.
        cards.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["Copied"].waitForExistence(timeout: 3) || app.otherElements["Copied"].exists)
        attach("02-copied-toast")

        // Long press opens the context menu with preview.
        cards.element(boundBy: 0).press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 3))
        attach("03-context-menu")
        app.buttons["Pin"].tap()
        attach("04-pin-submenu")
        dismissMenu()

        // Pinboards sheet.
        app.buttons["collectionButton"].tap()
        XCTAssertTrue(app.navigationBars["Pinboards"].waitForExistence(timeout: 3))
        attach("05-pinboards-sheet")
        app.descendants(matching: .any)["pinboardRow-Email Templates"].firstMatch.tap()
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 3))
        attach("06-pinboard-contents")
        app.buttons["collectionButton"].tap()
        XCTAssertTrue(app.navigationBars["Pinboards"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["pinboardRow-history"].firstMatch.tap()

        // Search with a filter token.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        attach("07-search-chips")
        app.descendants(matching: .any)["filterChip-kind:link"].firstMatch.tap()
        attach("08-search-link-filter")
        app.descendants(matching: .any)["filterChip-kind:link"].firstMatch.tap()
        search.typeText("meeting")
        attach("09-search-results")
        app.buttons["close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["selectButton"].waitForExistence(timeout: 3))

        // Select mode.
        app.buttons["selectButton"].tap()
        cards.element(boundBy: 0).tap()
        cards.element(boundBy: 2).tap()
        attach("10-select-mode")
        app.buttons["Done"].tap()
    }

    // MARK: - Helpers

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dismissMenu() {
        for _ in 0..<4 where app.buttons["Rename"].exists || app.buttons["New Pinboard…"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
            _ = app.buttons["Rename"].waitForNonExistence(timeout: 1.5)
        }
    }

    /// The Simulator sometimes shows an Apple Account sign-in alert on launch.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Not Now", "지금 안 함", "Cancel", "취소"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1.5) {
                button.tap()
                break
            }
        }
    }
}
