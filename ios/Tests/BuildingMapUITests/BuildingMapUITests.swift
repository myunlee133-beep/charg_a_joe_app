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
        let close = app.buttons["close-building-details"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["인문관1"].exists)
        XCTAssertTrue(app.staticTexts["1동"].exists)
        attachScreenshot(app, name: "building-from-map")

        app.buttons["expand-building-details"].tap()
        XCTAssertTrue(app.staticTexts["위치 정보"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "building-expanded")
        close.tap()
        XCTAssertFalse(close.exists)
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
        XCTAssertTrue(app.buttons["close-building-details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["인문관1"].exists)
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
