import XCTest

/// Walks the main iOS surfaces with demo data and attaches a screenshot of each.
/// Uses an in-memory store, so it never touches real clips.
final class ClipbaraiOSUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ClipbaraDemoData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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

    /// Needs the Clipbara keyboard enabled on the Simulator (scripts/ios-sim-enable-keyboard.sh).
    func testKeyboardTypesClipIntoTextField() throws {
        let cards = app.descendants(matching: .any).matching(identifier: "clipCard")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        attach("19-keyboard-after-focus")

        // The second card: the demo link, visible without scrolling the keyboard row.
        let clip = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "cloudkit/cksyncengine")).firstMatch
        // Cycle with the globe key until the Clipbara keyboard is up.
        let globeLabels = ["Next keyboard", "Next Keyboard", "다음 키보드", "지구본"]
        for _ in 0..<6 where !clip.waitForExistence(timeout: 2) {
            let globe = app.buttons.matching(NSPredicate(format: "label IN %@", globeLabels)).firstMatch
            guard globe.waitForExistence(timeout: 2) else { break }
            // Long-press opens the keyboard list; pick Clipbara directly instead of cycling.
            globe.press(forDuration: 1.2)
            let entry = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Clipbara")).firstMatch
            if entry.waitForExistence(timeout: 2) {
                entry.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
                globe.tap()
            }
        }
        XCTAssertTrue(clip.waitForExistence(timeout: 4), "Clipbara keyboard is not showing the demo clips")
        attach("20-keyboard")
        clip.tap()

        XCTAssertTrue(waitUntil(timeout: 4) {
            (search.value as? String)?.contains("https://developer.apple.com/documentation/cloudkit/cksyncengine") == true
        }, "Tapping the clip did not type it into the field")
        attach("21-keyboard-typed")

        // Pinboard switcher inside the keyboard.
        let board = app.buttons["Email Templates"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 3))
        board.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Out of office")).firstMatch.waitForExistence(timeout: 3))
        attach("22-keyboard-pinboard")
    }

    /// Share a clip through the system share sheet into the Clipbara share extension.
    /// The shared text lands in the inbox and is imported when the app is active again,
    /// which moves the matching clip back to the top of the history.
    func testShareExtensionSavesIntoHistory() throws {
        let cards = app.descendants(matching: .any).matching(identifier: "clipCard")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        let target = cards.matching(NSPredicate(format: "label CONTAINS %@", "Meeting moved to 3:30 PM")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 3))
        XCTAssertFalse(cards.element(boundBy: 0).label.contains("Meeting moved"))

        target.press(forDuration: 1.0)
        app.buttons["Share"].firstMatch.tap()

        let clipbaraLabel = NSPredicate(format: "label == %@", "Clipbara")
        let shareTarget = app.cells.matching(clipbaraLabel).firstMatch.exists
            ? app.cells.matching(clipbaraLabel).firstMatch
            : app.buttons.matching(clipbaraLabel).firstMatch
        if !shareTarget.waitForExistence(timeout: 5) {
            // The extension may be tucked behind "More" in the app row.
            let more = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["More", "기타"])).firstMatch
            if more.waitForExistence(timeout: 2) { more.tap() }
        }
        attach("40-share-sheet")
        let candidates = [app.cells.matching(clipbaraLabel).firstMatch, app.buttons.matching(clipbaraLabel).firstMatch]
        let hit = candidates.first { $0.waitForExistence(timeout: 3) && $0.isHittable }
        XCTAssertNotNil(hit, "Clipbara is not in the share sheet")
        hit?.tap()
        attach("41-share-saving")

        XCTAssertTrue(waitUntil(timeout: 8) {
            cards.element(boundBy: 0).label.contains("Meeting moved to 3:30 PM")
        }, "Shared clip was not imported to the top of the history")
        attach("42-share-imported")
    }

    /// Live CloudKit round trip with a Mac running the same build. Runs only when the
    /// runner gets CBSYNC_TOKEN (TEST_RUNNER_CBSYNC_TOKEN for xcodebuild). The Mac must
    /// already have saved "CBSYNC-mac-<token>", and the Simulator pasteboard must hold
    /// "CBSYNC-ios-<token>".
    func testSyncRoundTrip() throws {
        guard let token = ProcessInfo.processInfo.environment["CBSYNC_TOKEN"] else {
            throw XCTSkip("Live sync test runs only with CBSYNC_TOKEN")
        }
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        dismissSystemAlerts()

        // Turn sync on through Settings.
        app.buttons["More"].firstMatch.tap()
        app.buttons["Settings"].firstMatch.tap()
        let toggle = app.switches["iCloud Sync"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) != "1" {
            toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
            let turnOn = app.buttons["Turn On"].firstMatch
            XCTAssertTrue(turnOn.waitForExistence(timeout: 5))
            turnOn.tap()
        }
        let upToDate = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Up to date")).firstMatch
        XCTAssertTrue(upToDate.waitForExistence(timeout: 60), "Sync did not reach Up to date")
        attach("50-sync-on")
        app.buttons["Done"].firstMatch.tap()

        // Mac -> iPhone.
        let cards = app.descendants(matching: .any).matching(identifier: "clipCard")
        let macCard = cards.matching(NSPredicate(format: "label CONTAINS %@", "CBSYNC-mac-\(token)")).firstMatch
        XCTAssertTrue(macCard.waitForExistence(timeout: 90), "Clip from the Mac did not arrive")
        attach("51-mac-clip-arrived")

        // iPhone -> Mac: save the Simulator clipboard with the paste button.
        let iosText = "CBSYNC-ios-\(token)"
        let iosCard = cards.matching(NSPredicate(format: "label CONTAINS %@", iosText)).firstMatch
        app.buttons["pasteButton"].firstMatch.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        XCTAssertTrue(iosCard.waitForExistence(timeout: 10), "Saving the iPhone clipboard failed")

        // Pin the iPhone clip to a new pinboard.
        iosCard.press(forDuration: 1.0)
        app.buttons["Pin"].firstMatch.tap()
        app.buttons["New Pinboard…"].firstMatch.tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.typeText("CBSYNC-board-\(token)")
        app.buttons["Create"].firstMatch.tap()

        // Delete the Mac clip here; the Mac should drop it too.
        macCard.press(forDuration: 1.0)
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(macCard.waitForNonExistence(timeout: 5))

        // Give the engine time to send, then confirm the status.
        RunLoop.current.run(until: Date().addingTimeInterval(8))
        app.buttons["More"].firstMatch.tap()
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(upToDate.waitForExistence(timeout: 60))
        attach("52-after-local-changes")
        app.buttons["Done"].firstMatch.tap()
        attach("53-final-grid")
    }

    /// One-time Simulator setup: Settings > Apps > Clipbara > Keyboards > Clipbara.
    func testEnableKeyboardInSettings() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()
        func tapCell(_ labels: [String], swipes: Int = 8) -> Bool {
            let predicate = NSPredicate(format: "label IN %@", labels)
            for _ in 0...swipes {
                let cell = settings.cells.containing(predicate).firstMatch
                let text = settings.staticTexts.matching(predicate).firstMatch
                if cell.exists && cell.isHittable { cell.tap(); return true }
                if text.exists && text.isHittable { text.tap(); return true }
                settings.swipeUp()
            }
            return false
        }
        XCTAssertTrue(tapCell(["Apps", "앱"]), "Apps row not found")
        XCTAssertTrue(tapCell(["Clipbara"]), "Clipbara row not found")
        XCTAssertTrue(tapCell(["Keyboards", "키보드"]), "Keyboards row not found")
        let toggle = settings.switches.matching(NSPredicate(format: "label CONTAINS %@", "Clipbara")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        if (toggle.value as? String) != "1" { toggle.tap() }
        attachScreenshot(of: settings, name: "30-settings-keyboard-enabled")
    }

    // MARK: - Helpers

    private func attachScreenshot(of target: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: target.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

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
