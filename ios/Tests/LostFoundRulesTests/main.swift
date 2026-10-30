import Foundation


private func expectTrue(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    precondition(condition(), "Expected true", file: file, line: line)
}
private func expectFalse(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    precondition(!condition(), "Expected false", file: file, line: line)
}
private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    precondition(actual == expected, "Unexpected value", file: file, line: line)
}
private func expectNil<T>(_ actual: T?, file: StaticString = #filePath, line: UInt = #line) {
    precondition(actual == nil, "Expected nil", file: file, line: line)
}

struct LostFoundRulesTests {
    func testLocationLengthMatchesDatabaseBoundary() {
        expectFalse(LostFoundRules.validLocation("A"))
        expectTrue(LostFoundRules.validLocation("AB"))
        expectTrue(LostFoundRules.validLocation(String(repeating: "A", count: 120)))
        expectFalse(LostFoundRules.validLocation(String(repeating: "A", count: 121)))
        expectFalse(LostFoundRules.validLocation(String(repeating: "A", count: 160)))
    }

    func testKoreanAndSurroundingWhitespace() {
        expectTrue(LostFoundRules.validLocation(" \n" + String(repeating: "가", count: 120) + "\n "))
        expectFalse(LostFoundRules.validLocation(String(repeating: "가", count: 121)))
        expectFalse(LostFoundRules.validLocation(" \n "))
    }

    func testComposedCharactersUseDatabaseLength() {
        // Each e + combining accent is one grapheme but two PostgreSQL characters.
        expectTrue(LostFoundRules.validLocation(String(repeating: "e\u{301}", count: 60)))
        expectFalse(LostFoundRules.validLocation(String(repeating: "e\u{301}", count: 61)))
        expectFalse(LostFoundRules.validLocation(String(repeating: "👨‍👩‍👧‍👦", count: 18)))
    }

    func testBuildingNameCountsTowardLimit() {
        let building = "학생회관"
        let atLimit = LostFoundRules.locationName(buildingTitle: building, detail: String(repeating: "가", count: 113), direct: false)!
        expectTrue(LostFoundRules.validLocation(atLimit))
        let overLimit = LostFoundRules.locationName(buildingTitle: building, detail: String(repeating: "가", count: 114), direct: false)!
        expectFalse(LostFoundRules.validLocation(overLimit))
    }

    func testDirectLocationAndMissingFields() {
        expectEqual(LostFoundRules.locationName(buildingTitle: "학생회관", detail: "  관악경찰서 민원실  ", direct: true), "관악경찰서 민원실")
        expectNil(LostFoundRules.locationName(buildingTitle: nil, detail: "101호", direct: false))
        expectNil(LostFoundRules.locationName(buildingTitle: "학생회관", detail: " \n ", direct: false))
    }
}

let tests = LostFoundRulesTests()
let cases: [(String, () -> Void)] = [
    ("location database boundary", tests.testLocationLengthMatchesDatabaseBoundary),
    ("Korean and whitespace", tests.testKoreanAndSurroundingWhitespace),
    ("composed database characters", tests.testComposedCharactersUseDatabaseLength),
    ("combined building name", tests.testBuildingNameCountsTowardLimit),
    ("direct location and missing fields", tests.testDirectLocationAndMissingFields)
]
for (name, test) in cases {
    test()
    print("PASS " + name)
}
print("Passed \(cases.count) lost-found location tests")
