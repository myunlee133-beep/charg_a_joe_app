import XCTest

final class PlaceDiscoveryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testLabSummaryDisclosureAndReturnPreserveSearch() {
        exerciseLab(largeText: false)
    }

    func testLabAtAccessibilityTextSize() {
        exerciseLab(largeText: true)
    }

    private func exerciseLab(largeText: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-preview-place-building", "301"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let floors = app.buttons["building.floors"]
        XCTAssertTrue(floors.waitForExistence(timeout: 20))
        capture(app, largeText ? "large-01-building" : "01-building")
        floors.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("강유")
        let lab = app.buttons["lab.cse-1"]
        XCTAssertTrue(lab.waitForExistence(timeout: 5))
        capture(app, largeText ? "large-02-search" : "02-search")
        lab.tap()
        XCTAssertTrue(app.staticTexts["강유 교수"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["lab.description"].exists)
        if largeText { app.swipeUp() }
        let disclosure = app.buttons["lab.disclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        capture(app, largeText ? "large-03-lab" : "03-lab")
        if !disclosure.isHittable { app.swipeUp() }
        disclosure.tap()
        if !app.staticTexts["lab.description"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["lab.description"].waitForExistence(timeout: 5))
        capture(app, largeText ? "large-04-expanded" : "04-expanded")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["lab.cse-1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "강유")
    }

    func testCafeOfficialPhotosMenuDetailAndRestaurantControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-preview-place-building", "111"]
        app.launch()
        let food = app.buttons["building.food"]
        XCTAssertTrue(food.waitForExistence(timeout: 20)); food.tap()
        let cafe = app.buttons["venue.cafe-111"]
        XCTAssertTrue(cafe.waitForExistence(timeout: 5)); cafe.tap()
        XCTAssertTrue(app.buttons["cafe.featured"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["바닐라빈 골든라떼 공식 메뉴 사진"].firstMatch.exists)
        capture(app, "05-cafe-photo-menu")
        app.buttons["cafe.featured"].tap()
        XCTAssertTrue(app.navigationBars["메뉴 상세"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["가격은 매장에서 확인"].exists)
        capture(app, "06-menu-detail")
        app.navigationBars.buttons.firstMatch.tap()
        app.swipeDown()
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["building-explorer.close"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "식당")).firstMatch.tap()
        XCTAssertTrue(app.buttons["전날 식단"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["다음날 식단"].exists)
        XCTAssertTrue(app.buttons["dining.cafes"].exists)
        capture(app, "07-original-restaurant")
        app.buttons["dining.cafes"].tap()
        XCTAssertTrue(app.buttons["venue.cafe-109"].waitForExistence(timeout: 5))
        app.buttons["venue.cafe-109"].tap()
        XCTAssertTrue(app.staticTexts["카페109 디저트 모음"].waitForExistence(timeout: 5))
        capture(app, "08-cafe109-collage")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
