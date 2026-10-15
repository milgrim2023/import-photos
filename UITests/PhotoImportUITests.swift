import XCTest

/// End-to-end smoke tests that drive the real app through its accessibility tree.
/// The app is launched in its Debug-only test mode (see App/UITestSupport.swift): fake open panel,
/// fixture photos, throwaway settings. Fixture layout (oldest -> newest by date):
///   BRAVO.ARW (+BRAVO.ARW.xmp), CHARLIE.JPG (+CHARLIE.xmp), ALPHA.JPG, Subfolder/DELTA.JPG
final class PhotoImportUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: helpers
    func launch(_ extra: [String] = []) {
        app.launchArguments = ["-UITesting"] + extra
        app.launch()
    }
    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    func cell(_ name: String) -> XCUIElement { element("cell-\(name)") }
    func chooseSourceAndDestination() {
        element("choose-source").click()
        XCTAssertTrue(cell("ALPHA.JPG").waitForExistence(timeout: 10), "grid did not appear")
        element("choose-destination").click()
        XCTAssertTrue(app.staticTexts["destination-label"].waitForExistence(timeout: 5))
    }
    /// Names of the visible photos in reading order (top-to-bottom, left-to-right).
    func gridOrder() -> [String] {
        let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'cell-'")).allElementsBoundByIndex
        return cells.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            .map { $0.identifier.replacingOccurrences(of: "cell-", with: "") }
    }
    func isSelected(_ name: String) -> Bool { (cell(name).value as? String) == "selected" }
    /// The string a SwiftUI text exposes (macOS puts it in `value`, sometimes in `label`).
    func text(_ id: String) -> String {
        let e = element(id)
        if let v = e.value as? String, !v.isEmpty { return v }
        return e.label
    }
    /// The number shown on a results tile (its accessibility label reads "4 Photos imported").
    func stat(_ title: String) -> String {
        element("stat-\(title)").label.split(separator: " ").first.map(String.init) ?? ""
    }
    var summary: String { text("selection-summary") }

    // MARK: tests
    func testLaunchShowsTheEmptyStateAndImportIsDisabled() {
        launch()
        XCTAssertTrue(element("choose-source").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["import-button"].isEnabled)
        XCTAssertEqual(summary, "Select files or folders to import")
        XCTAssertFalse(element("cancel-button").exists, "Cancel is only offered while importing")
    }

    func testChoosingASourceListsPhotosOldestFirstAndHidesSidecars() {
        launch()
        chooseSourceAndDestination()
        XCTAssertEqual(gridOrder(), ["Subfolder", "BRAVO.ARW", "CHARLIE.JPG", "ALPHA.JPG"])
        XCTAssertFalse(cell("BRAVO.ARW.xmp").exists)
        XCTAssertFalse(cell("CHARLIE.xmp").exists)
    }

    func testSortMenuReordersTheGrid() {
        launch()
        chooseSourceAndDestination()
        app.popUpButtons["sort-picker"].click()
        app.menuItems["Name"].click()
        XCTAssertEqual(gridOrder(), ["Subfolder", "ALPHA.JPG", "BRAVO.ARW", "CHARLIE.JPG"])
    }

    func testCaptureDateSortIsAvailableAndOrdersTheGrid() {
        launch()
        chooseSourceAndDestination()
        app.popUpButtons["sort-picker"].click()
        app.menuItems["Capture date (newest first)"].click()
        XCTAssertEqual(gridOrder(), ["Subfolder", "ALPHA.JPG", "CHARLIE.JPG", "BRAVO.ARW"])   // no EXIF in fixtures -> file dates
    }

    func testClickCommandClickAndShiftClickSelectLikeFinder() {
        launch()
        chooseSourceAndDestination()                       // order: Subfolder, BRAVO, CHARLIE, ALPHA

        cell("BRAVO.ARW").click()
        XCTAssertEqual(summary, "1 item selected")
        XCTAssertTrue(isSelected("BRAVO.ARW"))

        XCUIElement.perform(withKeyModifiers: .shift) { cell("ALPHA.JPG").click() }
        XCTAssertEqual(summary, "3 items selected", "shift-click should select the range BRAVO..ALPHA")
        XCTAssertTrue(isSelected("CHARLIE.JPG"))

        XCUIElement.perform(withKeyModifiers: .command) { cell("CHARLIE.JPG").click() }
        XCTAssertEqual(summary, "2 items selected", "command-click should toggle one item off")
        XCTAssertFalse(isSelected("CHARLIE.JPG"))

        cell("ALPHA.JPG").click()
        XCTAssertEqual(summary, "1 item selected", "plain click replaces the selection")
    }

    func testSelectAllThenImportShowsTheResultsSheetWithSidecarsNoted() {
        launch()
        chooseSourceAndDestination()
        element("select-all").click()
        XCTAssertEqual(summary, "4 items selected")      // Subfolder + 3 photos

        app.buttons["import-button"].click()

        XCTAssertTrue(element("results-title").waitForExistence(timeout: 20), "results sheet did not appear")
        XCTAssertEqual(text("results-title"), "Import Complete")
        XCTAssertEqual(stat("Photos imported"), "4")
        XCTAssertEqual(stat("Skipped (duplicates)"), "0")
        XCTAssertTrue(element("sidecar-note").exists, "sidecars copied implicitly should be noted")
    }

    func testCancelMidImportKeepsFinishedFilesAndReportsTheRest() {
        launch(["-UITestSlowImport"])
        chooseSourceAndDestination()
        element("select-all").click()                              // Subfolder + 3 photos = 4 files at ~1 s each
        app.buttons["import-button"].click()

        XCTAssertTrue(element("cancel-button").waitForExistence(timeout: 5), "Cancel is offered while importing")
        element("cancel-button").click()

        XCTAssertTrue(element("results-title").waitForExistence(timeout: 20))
        XCTAssertEqual(text("results-title"), "Import Cancelled")
        XCTAssertTrue(element("cancelled-note").exists, "files not reached are reported")
        let imported = Int(stat("Photos imported")) ?? -1
        XCTAssertTrue((0..<4).contains(imported), "some, but not all, files were imported (got \(imported))")
    }

    func testImportingTwiceReportsEverythingAsSkipped() {
        launch()
        chooseSourceAndDestination()
        element("select-all").click()
        app.buttons["import-button"].click()
        XCTAssertTrue(element("results-title").waitForExistence(timeout: 20))
        element("results-done").click()
        XCTAssertTrue(app.buttons["import-button"].waitForExistence(timeout: 5))

        app.buttons["import-button"].click()

        XCTAssertTrue(element("results-title").waitForExistence(timeout: 20))
        XCTAssertEqual(stat("Photos imported"), "0")
        XCTAssertEqual(stat("Skipped (duplicates)"), "4")
    }

    func testPickingIndividualPhotosWithoutTheirSidecarsShowsTheWarning() {
        launch(["-UITestPickFiles", "-UITestCannotListFolders"])
        element("choose-source").click()
        XCTAssertTrue(cell("ALPHA.JPG").waitForExistence(timeout: 10))
        XCTAssertTrue(element("sidecar-warning").waitForExistence(timeout: 5))
        XCTAssertEqual(summary, "2 items selected", "picked photos are pre-selected")
    }

    func testOffsetQuickButtonUpdatesTheLabelAndKeepsThePreviewPath() {
        launch()
        chooseSourceAndDestination()
        cell("BRAVO.ARW").click()
        XCTAssertTrue(element("preview-saved-as").waitForExistence(timeout: 5))
        XCTAssertEqual(text("preview-saved-as"), "2024/06/BRAVO.ARW")

        app.buttons["offset-plus-1h"].click()          // +1 hour keeps 12:00 inside June 10
        XCTAssertEqual(text("offset-label"), "+1")
        XCTAssertEqual(text("preview-saved-as"), "2024/06/BRAVO.ARW")
        app.buttons["offset-reset"].click()
        XCTAssertEqual(text("offset-label"), "0")
    }
}
