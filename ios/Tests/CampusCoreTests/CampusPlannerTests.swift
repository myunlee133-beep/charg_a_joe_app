import XCTest
@testable import CampusCore

final class CampusPlannerTests: XCTestCase {
    private func course(_ start: Int, _ end: Int, day: Int = 3) -> CampusClass {
        .init(title: "등록 수업", weekday: day, startMinute: start, endMinute: end, buildingNumber: "64", room: "201")
    }
    func testOverlappingAndAdjacentClassesAreHandledWithoutFalseFreeTime() {
        let classes = [course(540, 660), course(630, 720), course(720, 780)]
        XCTAssertEqual(CampusPlanning.freeRanges(classes: classes, weekday: 3, within: .init(start: 540, end: 1080)), [.init(start: 780, end: 1080)])
    }
    func testClassesOnOtherDaysDoNotBlockThisDay() {
        XCTAssertEqual(CampusPlanning.freeRanges(classes: [course(540, 1080, day: 2)], weekday: 3, within: .init(start: 540, end: 1080)), [.init(start: 540, end: 1080)])
    }
    func testOnlySufficientGapsInsideOpeningHoursAreSuggested() {
        let result = CampusPlanning.visitRanges(classes: [course(600, 710), course(720, 900)], weekday: 3, openingHours: [.init(start: 660, end: 1080)])
        XCTAssertEqual(result, [.init(start: 900, end: 1080)])
    }
    func testOverlappingVenueHoursAreMerged() {
        XCTAssertEqual(CampusPlanning.visitRanges(classes: [], weekday: 3, openingHours: [.init(start: 540, end: 900), .init(start: 660, end: 1080)], after: 780), [.init(start: 780, end: 1080)])
    }
    func testElapsedHoursAndInvalidWindowsHaveNoRecommendation() {
        XCTAssertTrue(CampusPlanning.visitRanges(classes: [], weekday: 3, openingHours: [.init(start: 540, end: 600)], after: 660).isEmpty)
        XCTAssertTrue(CampusPlanning.freeRanges(classes: [], weekday: 9, within: .init(start: 0, end: 60)).isEmpty)
        XCTAssertTrue(CampusPlanning.freeRanges(classes: [], weekday: 3, within: .init(start: -1, end: 60)).isEmpty)
    }
    func testInvalidAndOvernightClassesAreRejected() {
        XCTAssertFalse(course(600, 540).isValid)
        XCTAssertFalse(course(600, 600).isValid)
        XCTAssertFalse(course(-1, 60).isValid)
        XCTAssertFalse(course(600, 1500).isValid)
        XCTAssertTrue(course(1380, 1440).isValid)
    }
    func testConflictDetectionExcludesTheEditedClass() {
        let original = course(540, 600)
        XCTAssertFalse(CampusPlanning.conflicts(original, with: [original]))
        XCTAssertTrue(CampusPlanning.conflicts(course(570, 630), with: [original]))
        XCTAssertFalse(CampusPlanning.conflicts(course(600, 660), with: [original]))
    }
    func testHoursParsingDoesNotInventClosedOrUnpublishedHours() {
        XCTAssertEqual(CampusPlanning.parseHours("08:30–18:30 / 19:00-21:00"), [.init(start: 510, end: 1110), .init(start: 1140, end: 1260)])
        XCTAssertTrue(CampusPlanning.parseHours("휴무 / 미등록").isEmpty)
        XCTAssertTrue(CampusPlanning.parseHours("09:90–21:00").isEmpty)
        XCTAssertTrue(CampusPlanning.parseHours("22:00–02:00").isEmpty)
    }
    func testPlannerDataRoundTripsWithoutBackendOrExampleRecords() throws {
        let empty = CampusPlannerData()
        XCTAssertTrue(empty.classes.isEmpty); XCTAssertTrue(empty.tasks.isEmpty)
        let data = CampusPlannerData(classes: [course(540, 600)], tasks: [.init(title: "도서 찾기", buildingID: "snu-80", location: "1층", due: Date(timeIntervalSince1970: 1_800_000_000))], favoriteBuildings: ["snu-80"])
        XCTAssertEqual(try JSONDecoder().decode(CampusPlannerData.self, from: JSONEncoder().encode(data)), data)
    }
    func testScheduleUsesSeoulTimeAndOnlyNextClassToday() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-24T03:00:00Z"))
        XCTAssertEqual(CampusPlanning.minute(of: date, calendar: CampusPlanning.calendar), 720)
        let classes = [course(540, 600), course(900, 960), course(780, 840, day: 4)]
        XCTAssertEqual(CampusPlanning.nextClass(classes, on: date, calendar: CampusPlanning.calendar)?.startMinute, 900)
    }
    func testPhotographsAndSpacesHaveRegisteredBuildingIdentities() throws {
        XCTAssertGreaterThan(CampusBuildingPhoto.all.count, 200)
        let numbers = Set(CampusBuildingCatalog.all.map(\.id))
        XCTAssertTrue(CampusBuildingPhoto.all.allSatisfy { numbers.contains($0.buildingID) && $0.remoteURL != nil })
        XCTAssertEqual(CampusBuildingPhoto.all.filter { $0.assetName != nil }.count, 12)
        XCTAssertFalse(CampusSpace.all.isEmpty)
        XCTAssertTrue(CampusSpace.all.allSatisfy { numbers.contains($0.building.id) })
    }
    func testStudyRecommendationsExcludeLibraryATMsOfficesParkingAndAEDs() {
        let names = Set(CampusSpace.all.map(\.name))
        XCTAssertTrue(names.contains("중앙도서관 본관"))
        XCTAssertTrue(names.contains("사회과학도서관"))
        XCTAssertFalse(names.contains("중앙도서관 농협ATM"))
        XCTAssertFalse(names.contains("중앙도서관 수서정리과 사무실"))
        XCTAssertFalse(names.contains("62동 중앙도서관 본관: 3층 3A 열람실 출입구"))
        XCTAssertFalse(names.contains("관정관: 2층 헤리티지 라운지"))
        XCTAssertEqual(CampusSpace.all.filter { $0.name == "농학도서관" }.count, 1)
    }
}
