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
        let knownCard = cards.matching(NSPredicate(format: "label CONTAINS %@", "Škoda Octavia")).firstMatch
        XCTAssertTrue(knownCard.label.contains("Rare"))
        XCTAssertTrue(knownCard.label.contains("100 XP"))
        let unknownCard = cards.matching(NSPredicate(format: "label CONTAINS %@", "Unknown Car")).firstMatch
        XCTAssertTrue(unknownCard.label.contains("Undetermined Rarity"))
        XCTAssertTrue(unknownCard.label.contains("25 XP"))

        // Search ignores case and diacritics.
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("skoda")
        XCTAssertEqual(cards.count, 1)
    }

    func testCropFrameFollowsMoveAndResizeDrag() {
        launch()
        importTestPhoto()
        app.buttons["regions.add"].tap()
        let crop = app.descendants(matching: .any)["regions.frame.1"].firstMatch
        XCTAssertTrue(crop.waitForExistence(timeout: 5))
        let original = crop.frame
        let start = crop.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 50, dy: 30)),
                    withVelocity: .slow, thenHoldForDuration: 0.1)
        let moved = crop.frame
        XCTAssertEqual(moved.minX, original.minX + 50, accuracy: 4)
        XCTAssertEqual(moved.minY, original.minY + 30, accuracy: 4)
        XCTAssertEqual(moved.width, original.width, accuracy: 2)
        XCTAssertEqual(moved.height, original.height, accuracy: 2)

        // The resize target is centered 22 points inside the bottom-right corner.
        let handle = crop.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -22, dy: -22))
        handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(CGVector(dx: -40, dy: -25)),
                     withVelocity: .slow, thenHoldForDuration: 0.1)
        let resized = crop.frame
        XCTAssertEqual(resized.minX, moved.minX, accuracy: 2)
        XCTAssertEqual(resized.minY, moved.minY, accuracy: 2)
        XCTAssertEqual(resized.width, moved.width - 40, accuracy: 4)
        XCTAssertEqual(resized.height, moved.height - 25, accuracy: 4)

        // A vertical drag must move the car, rather than scroll the enclosing page.
        let center = crop.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 0, dy: -30)),
                     withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertEqual(crop.frame.minX, resized.minX, accuracy: 2)
        XCTAssertEqual(crop.frame.minY, resized.minY - 30, accuracy: 4)
        XCTAssertEqual(crop.frame.size.width, resized.width, accuracy: 2)
        XCTAssertEqual(crop.frame.size.height, resized.height, accuracy: 2)
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
