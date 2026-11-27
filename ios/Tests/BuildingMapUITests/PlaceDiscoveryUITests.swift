import XCTest

final class PlaceDiscoveryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testBuildingPreviewAndPharmacyDetail() { exercisePharmacy(largeText: false) }
    func testPharmacyAtAccessibilityTextSize() { exercisePharmacy(largeText: true) }

    private func exercisePharmacy(largeText: Bool) {
        let app = XCUIApplication()
        if largeText { app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20)); search.tap(); search.typeText("63")
        let hall = app.buttons["building-result-snu-80"]
        XCTAssertTrue(hall.waitForExistence(timeout: 10)); hall.tap()
        XCTAssertTrue(app.buttons["expand-building-details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["building.kind.pharmacy"].exists)
        capture(app, largeText ? "amenity-large-01-preview" : "amenity-01-building-preview")
        app.buttons["building.kind.pharmacy"].tap()
        let pharmacy = app.buttons["amenity.snu-amenity-196"]
        XCTAssertTrue(app.buttons["building-explorer.close"].waitForExistence(timeout: 10))
        for _ in 0..<7 where !pharmacy.isHittable { app.swipeUp() }
        XCTAssertTrue(pharmacy.exists)
        capture(app, largeText ? "amenity-large-02-floor" : "amenity-02-pharmacy-floor")
        pharmacy.tap()
        XCTAssertTrue(app.navigationBars["시설 상세"].waitForExistence(timeout: 5))
        if largeText { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["09:00–18:10"].exists)
        capture(app, largeText ? "amenity-large-03-detail" : "amenity-03-pharmacy-detail")
    }

    func testConvenienceFilterAndFacilitySearch() {
        let app = XCUIApplication(); app.launch()
        let amenities = app.buttons["map.amenities"]
        XCTAssertTrue(amenities.waitForExistence(timeout: 20)); amenities.tap()
        app.buttons["map-amenity-filter.pharmacy"].tap()
        let pharmacy = app.buttons["amenity-browse-snu-amenity-196"]
        XCTAssertTrue(pharmacy.waitForExistence(timeout: 5))
        capture(app, "amenity-04-map-filter")
        let search = app.textFields.firstMatch
        search.tap(); search.typeText("CU")
        let convenience = app.buttons["amenity-result-snu-amenity-111"]
        XCTAssertTrue(convenience.waitForExistence(timeout: 5))
        capture(app, "amenity-05-cu-search")
        convenience.tap()
        XCTAssertTrue(app.navigationBars["시설 상세"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["CU"].exists)
        XCTAssertTrue(app.staticTexts["24시간 · 유인 08:00–22:00"].exists)
        capture(app, "amenity-06-convenience-detail")
    }

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
        XCTAssertTrue(app.buttons["building-explorer.close"].waitForExistence(timeout: 20))
        for _ in 0..<3 where !floors.exists || !floors.isHittable { app.swipeUp() }
        XCTAssertTrue(floors.exists)
        capture(app, largeText ? "large-01-building" : "01-building")
        floors.tap()
        app.buttons["building.facility-search"].tap()
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
        let disclosure = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "연구실 설명")).firstMatch
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
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["building-explorer.close"].tap()
        app.buttons["main-tab-식당"].tap()
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

    func testStudentHallReferenceHubAndHonestFacilityStatus() {
        let app = XCUIApplication()
        app.launchArguments = ["-preview-place-building", "63"]
        app.launch()
        XCTAssertTrue(app.buttons["building.home"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.images["학생회관 공식 건물 사진"].exists)
        capture(app, "reference-01-student-hall-home")
        let favorite = app.buttons["building.favorite"]
        let before = favorite.label; favorite.tap(); XCTAssertNotEqual(before, favorite.label)
        let status = app.buttons["building.status"]
        if !status.isHittable { app.swipeUp() }
        status.tap()
        XCTAssertTrue(app.staticTexts["실시간 정보 연결 전"].waitForExistence(timeout: 5))
        capture(app, "reference-02-facility-status")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["building.food"].tap()
        capture(app, "reference-03-student-hall-food")
        app.buttons["building.guide"].tap()
        capture(app, "reference-04-guide")
    }

    func testTimetableAndTasksPersistAcrossLaunches() {
        let app = XCUIApplication()
        app.launchArguments = ["-preview-place-building", "63"]
        app.launch()
        XCTAssertTrue(app.buttons["building.home"].waitForExistence(timeout: 20))
        let timetable = app.buttons["building.timetable"]
        for _ in 0..<4 where !timetable.isHittable { app.swipeUp() }
        timetable.tap()
        app.buttons["planner.add-class"].tap()
        let name = app.textFields["class.title"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("UI 검증 수업")
        app.textFields["class.building"].tap(); app.textFields["class.building"].typeText("64")
        app.buttons["class.save"].tap()
        XCTAssertTrue(app.staticTexts["UI 검증 수업"].waitForExistence(timeout: 5))
        capture(app, "reference-05-timetable")
        app.buttons["방문 추천 시간"].tap()
        capture(app, "reference-06-visit-time")
        app.navigationBars.buttons.firstMatch.tap()
        let tasks = app.buttons["building.tasks"]
        for _ in 0..<3 where !tasks.isHittable { app.swipeDown() }
        tasks.tap(); app.buttons["planner.add-task"].tap()
        app.textFields["task.title"].tap(); app.textFields["task.title"].typeText("UI 검증 방문")
        app.buttons["task.save"].tap()
        XCTAssertTrue(app.staticTexts["UI 검증 방문"].waitForExistence(timeout: 5))
        capture(app, "reference-07-tasks")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["building-explorer.close"].waitForExistence(timeout: 15))
        for _ in 0..<4 where !app.staticTexts["UI 검증 방문"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["UI 검증 방문"].waitForExistence(timeout: 15))
    }
}
