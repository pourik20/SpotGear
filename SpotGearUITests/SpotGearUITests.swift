import XCTest

/// End-to-end flows on an isolated data directory with the synthetic test photo (DEBUG only).
final class SpotGearUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ extraArguments: [String] = []) {
        app.launchArguments = ["-ui-testing", "-ui-reset"] + extraArguments
        app.launch()
    }

    private func importTestPhoto() {
        app.navigationBars.buttons["Add Photo"].tap()
        app.buttons["Sample Photo"].tap()
        XCTAssertTrue(app.buttons["regions.add"].waitForExistence(timeout: 10))
    }

    private func openSummaryRow(_ index: Int) {
        // Matched by label: the collection under the import sheet also exposes cells.
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Car \(index + 1),")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    /// Form rows below the card preview are created lazily, so scroll until the element is hittable.
    @discardableResult
    private func scrolledTo(_ element: XCUIElement, timeout: TimeInterval = 10) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while !(element.exists && element.isHittable), Date() < deadline {
            app.swipeUp()
        }
        return element
    }

    private func confirmUnknown() {
        scrolledTo(app.buttons["identity.unknown"]).tap()
        app.buttons["region.confirm"].tap()
    }

    func testOfflineImportOfTwoCarsManualAndUnknown() {
        launch()
        importTestPhoto()
        app.buttons["regions.add"].tap()
        app.buttons["regions.add"].tap()
        app.buttons["regions.continue"].tap()

        openSummaryRow(0)
        XCTAssertTrue(app.staticTexts["suggestions.unavailable"].waitForExistence(timeout: 5))
        let make = scrolledTo(app.textFields["identity.make"])
        make.tap()
        make.typeText("Škoda")
        let model = app.textFields["identity.model"]
        model.tap()
        model.typeText("Octavia")
        app.buttons["region.confirm"].tap()

        openSummaryRow(1)
        confirmUnknown()

        let save = app.buttons["summary.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let cards = app.descendants(matching: .any).matching(identifier: "spot.card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(cards.count, 2)

        // Search ignores case and diacritics.
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("skoda")
        XCTAssertEqual(cards.count, 1)
    }

    func testDetectedCarsSkipManualSelectionAndShowCatalogInfo() {
        launch(["-ui-fake-detector"])
        app.navigationBars.buttons["Add Photo"].tap()
        app.buttons["Sample Photo"].tap()

        openSummaryRow(0)
        let make = scrolledTo(app.textFields["identity.make"])
        make.tap()
        make.typeText("Škoda")
        let model = app.textFields["identity.model"]
        model.tap()
        model.typeText("Octavia")
        XCTAssertTrue(scrolledTo(app.staticTexts["insight.price"]).exists)
        scrolledTo(app.buttons["region.confirm"]).tap()

        openSummaryRow(1)
        confirmUnknown()
        app.buttons["summary.save"].tap()

        let cards = app.descendants(matching: .any).matching(identifier: "spot.card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(cards.count, 2)
    }

    func testFavoriteEditAndDelete() {
        launch()
        importTestPhoto()
        app.buttons["regions.add"].tap()
        app.buttons["regions.continue"].tap()
        openSummaryRow(0)
        confirmUnknown()
        app.buttons["summary.save"].tap()

        let card = app.descendants(matching: .any).matching(identifier: "spot.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        app.buttons["detail.favorite"].tap()
        app.buttons["detail.editIdentity"].tap()
        let make = app.textFields["identity.make"]
        make.tap()
        make.typeText("Tatra")
        app.buttons["identity.save"].tap()
        XCTAssertTrue(app.staticTexts["Tatra"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["collection.favoritesOnly"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        card.tap()
        scrolledTo(app.buttons["detail.delete"]).tap()
        app.sheets.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Your Garage Starts Here"].waitForExistence(timeout: 5))
    }

    func testFailedSaveCanBeRetriedWithoutDuplicates() {
        launch(["-ui-fail-first-save"])
        importTestPhoto()
        app.buttons["regions.add"].tap()
        app.buttons["regions.continue"].tap()
        openSummaryRow(0)
        confirmUnknown()

        app.buttons["summary.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["summary.saveError"].waitForExistence(timeout: 10))

        app.buttons["summary.save"].tap()
        let cards = app.descendants(matching: .any).matching(identifier: "spot.card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(cards.count, 1)
    }

    func testFakeSuggestionsRequireConfirmation() {
        launch(["-ui-fake-identifier"])
        importTestPhoto()
        app.buttons["regions.add"].tap()
        app.buttons["regions.continue"].tap()
        openSummaryRow(0)

        XCTAssertTrue(scrolledTo(app.buttons["suggestions.none"]).isHittable)
        app.buttons["suggestions.none"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.buttons["summary.save"].isEnabled)
    }
}
