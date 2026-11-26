import XCTest

final class BuildingMapUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testMapTapOpensBuildingDetailsAndCanExpandAndClose() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-preview-map-building-center", "snu-1"]
        app.launch()
        let map = app.otherElements["campus-map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 30))
        let ready = NSPredicate(format: "value == %@", "지도를 사용할 수 있습니다")
        expectation(for: ready, evaluatedWith: map)
        waitForExpectations(timeout: 30)

        // This is a real SDK map touch at the unselected building's coordinate,
        // not a launch argument that opens the card for us.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let close = app.buttons["building-explorer.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["인문관1"].exists)
        attachScreenshot(app, name: "building-from-map")

        XCTAssertTrue(app.buttons["building.floors"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "building-overview")
        app.buttons["building-explorer.close"].tap()
        let zoomIn = app.buttons["지도 확대"]
        XCTAssertTrue(zoomIn.isHittable)
        XCTAssertGreaterThanOrEqual(zoomIn.frame.minY, searchControlsBottom(in: app))
        attachScreenshot(app, name: "building-summary")
        app.buttons["close-building-details"].tap()
        XCTAssertFalse(app.buttons["close-building-details"].exists)
    }

    func testSearchBuildingReplacesSelectedQuestCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-preview-map-selected"]
        app.launch()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText("1")
        let result = app.buttons["building-result-snu-1"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        XCTAssertTrue(app.buttons["building-explorer.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["인문관1"].exists)
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func searchControlsBottom(in app: XCUIApplication) -> CGFloat {
        app.buttons.matching(NSPredicate(format: "label == %@", "전체")).firstMatch.frame.maxY
    }
}
