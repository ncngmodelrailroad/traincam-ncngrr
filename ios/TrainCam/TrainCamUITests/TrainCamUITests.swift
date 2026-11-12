import XCTest

final class TrainCamUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Launch & Navigation

    func testAppLaunchesSuccessfully() throws {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    func testNavigationTitleVisible() throws {
        let title = app.navigationBars["RailCam"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Navigation bar should show 'TrainCam' title")
    }

    // MARK: - Empty / Scanning State

    func testScanningOrEmptyStateVisible() throws {
        // Either scanning indicator or empty-state message should appear
        let scanning = app.staticTexts["Scanning for cameras..."]
        let empty = app.staticTexts["No Cameras Found"]
        let found = scanning.waitForExistence(timeout: 3) || empty.waitForExistence(timeout: 5)
        XCTAssertTrue(found, "Should show scanning indicator or empty state")
    }

    // MARK: - Toolbar Buttons

    func testAboutButtonExists() throws {
        let aboutButton = app.navigationBars.buttons["About RailCam"]
        XCTAssertTrue(aboutButton.waitForExistence(timeout: 5), "About button should exist in toolbar")
    }

    func testAboutButtonOpensSheet() throws {
        let aboutButton = app.navigationBars.buttons["About RailCam"]
        XCTAssertTrue(aboutButton.waitForExistence(timeout: 5))
        aboutButton.tap()

        let aboutTitle = app.staticTexts["RailCam"]
        XCTAssertTrue(aboutTitle.waitForExistence(timeout: 3), "About sheet should show app name")

        let versionText = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Version'"))
        XCTAssertTrue(versionText.count > 0, "About sheet should show version info")
    }

    func testMenuButtonExists() throws {
        let menuButton = app.navigationBars.buttons["Camera options"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5), "Menu button should exist in toolbar")
    }

    // MARK: - Manual Add Flow

    func testManualAddShowsAlert() throws {
        let menuButton = app.navigationBars.buttons["Camera options"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))
        menuButton.tap()

        let addButton = app.buttons["Add Camera by IP"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3), "Menu should contain Add Camera by IP option")
        addButton.tap()

        let alert = app.alerts["Add Camera"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "Add Camera alert should appear")

        let textField = alert.textFields["IP Address"]
        XCTAssertTrue(textField.exists, "Alert should have IP Address text field")

        let cancelButton = alert.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists, "Alert should have Cancel button")
        cancelButton.tap()
    }

    // MARK: - App Store Screenshots

    func testCaptureAppStoreScreenshots() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        sleep(3)

        // Screenshot 1: Camera list
        try saveScreenshot("01_camera_list", to: dir)

        // Screenshot 2: About sheet
        let aboutButton = app.navigationBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'About'")
        ).firstMatch
        if aboutButton.waitForExistence(timeout: 5) {
            aboutButton.tap()
            sleep(1)
            try saveScreenshot("02_about", to: dir)
            let done = app.buttons["Done"]
            if done.waitForExistence(timeout: 2) { done.tap() }
            sleep(1)
        }

        // Screenshot 3: Navigate to camera detail
        let card = app.scrollViews.otherElements.buttons.firstMatch
        if card.waitForExistence(timeout: 5) {
            card.tap()
            sleep(2)
            try saveScreenshot("03_camera_detail", to: dir)
        }

        // Screenshot 4: Try tapping the stream area or scrolling to telemetry
        app.swipeUp()
        sleep(1)
        try saveScreenshot("04_telemetry", to: dir)
    }

    private func saveScreenshot(_ name: String, to directory: URL) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let url = directory.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: url)
    }
}
