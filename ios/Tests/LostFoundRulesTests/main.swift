import XCTest

final class LostFoundRulesTests: XCTestCase {
    func testLocationLengthMatchesDatabaseBoundary() {
        XCTAssertFalse(LostFoundRules.validLocation("A"))
        XCTAssertTrue(LostFoundRules.validLocation("AB"))
        XCTAssertTrue(LostFoundRules.validLocation(String(repeating: "A", count: 120)))
        XCTAssertFalse(LostFoundRules.validLocation(String(repeating: "A", count: 121)))
        XCTAssertFalse(LostFoundRules.validLocation(String(repeating: "A", count: 160)))
    }

    func testKoreanAndSurroundingWhitespace() {
        XCTAssertTrue(LostFoundRules.validLocation(" \n" + String(repeating: "가", count: 120) + "\n "))
        XCTAssertFalse(LostFoundRules.validLocation(String(repeating: "가", count: 121)))
        XCTAssertFalse(LostFoundRules.validLocation(" \n "))
    }

    func testComposedCharactersUseDatabaseLength() {
        // Each e + combining accent is one grapheme but two PostgreSQL characters.
        XCTAssertTrue(LostFoundRules.validLocation(String(repeating: "e\u{301}", count: 60)))
        XCTAssertFalse(LostFoundRules.validLocation(String(repeating: "e\u{301}", count: 61)))
        XCTAssertFalse(LostFoundRules.validLocation(String(repeating: "👨‍👩‍👧‍👦", count: 18)))
    }

    func testBuildingNameCountsTowardLimit() {
        let building = "학생회관"
        let atLimit = LostFoundRules.locationName(buildingTitle: building, detail: String(repeating: "가", count: 113), direct: false)!
        XCTAssertTrue(LostFoundRules.validLocation(atLimit))
        let overLimit = LostFoundRules.locationName(buildingTitle: building, detail: String(repeating: "가", count: 114), direct: false)!
        XCTAssertFalse(LostFoundRules.validLocation(overLimit))
    }

    func testDirectLocationAndMissingFields() {
        XCTAssertEqual(LostFoundRules.locationName(buildingTitle: "학생회관", detail: "  관악경찰서 민원실  ", direct: true), "관악경찰서 민원실")
        XCTAssertNil(LostFoundRules.locationName(buildingTitle: nil, detail: "101호", direct: false))
        XCTAssertNil(LostFoundRules.locationName(buildingTitle: "학생회관", detail: " \n ", direct: false))
    }
}

XCTMain([testCase([
    ("testLocationLengthMatchesDatabaseBoundary", LostFoundRulesTests.testLocationLengthMatchesDatabaseBoundary),
    ("testKoreanAndSurroundingWhitespace", LostFoundRulesTests.testKoreanAndSurroundingWhitespace),
    ("testComposedCharactersUseDatabaseLength", LostFoundRulesTests.testComposedCharactersUseDatabaseLength),
    ("testBuildingNameCountsTowardLimit", LostFoundRulesTests.testBuildingNameCountsTowardLimit),
    ("testDirectLocationAndMissingFields", LostFoundRulesTests.testDirectLocationAndMissingFields)
])])
