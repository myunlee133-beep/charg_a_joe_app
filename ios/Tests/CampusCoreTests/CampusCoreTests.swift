import XCTest
@testable import CampusCore

final class CampusCoreTests: XCTestCase {
    func tracker() throws -> CircularShuttleTracker { try CircularShuttleTracker(route: XCTUnwrap(CircularRoute.load())) }
    func bus(_ y: Double, id: String = "100") -> CircularFeed.Vehicle { .init(id: id, x: 195, y: y) }
    func testBundledRouteAndAnchors() throws {
        let t = try tracker()
        XCTAssertEqual(t.route.routeId, "41946"); XCTAssertEqual(t.route.stops.count, 14)
        XCTAssertGreaterThan(t.totalRoadDistance, 4000); XCTAssertLessThan(t.totalRoadDistance, 12000)
        for stop in t.route.stops {
            t.clear(); t.update([.init(id: "1", x: stop.diagram[0], y: stop.diagram[1])], at: 0)
            XCTAssertLessThan(try XCTUnwrap(t.positions(at: 0).first).coordinate.distance(to: stop.coordinate), 35, stop.name)
        }
    }
    func testFirstReceiptAndStationaryCoordinates() throws {
        let t = try tracker(); t.update([bus(136)], at: 0)
        let start = try XCTUnwrap(t.positions(at: 0).first)
        XCTAssertNil(start.movementAge); XCTAssertEqual(start.changes, 0); XCTAssertEqual(start.nextStop, "농생대")
        t.update([bus(136)], at: 5)
        XCTAssertEqual(t.positions(at: 6).first?.coordinate, start.coordinate)
        XCTAssertNil(t.positions(at: 6).first?.movementAge)
    }
    func testNewCoordinatesInterpolateAndStopAtLastObservation() throws {
        let t = try tracker(); t.update([bus(136)], at: 0); let a = try XCTUnwrap(t.positions(at: 0).first)
        t.update([bus(138)], at: 5)
        let middle = try XCTUnwrap(t.positions(at: 5.6).first)
        let target = try XCTUnwrap(t.positions(at: 6.2).first)
        XCTAssertGreaterThan(a.coordinate.distance(to: middle.coordinate), 0)
        XCTAssertGreaterThan(middle.coordinate.distance(to: target.coordinate), 0)
        XCTAssertEqual(t.positions(at: 18).first?.coordinate, target.coordinate)
        XCTAssertEqual(target.changes, 1)
    }
    func testSmallChangesAccumulate() throws {
        let t = try tracker(); t.update([bus(136)], at: 0); t.update([bus(136.4)], at: 5)
        XCTAssertEqual(t.positions(at: 5).first?.changes, 0)
        t.update([bus(136.8)], at: 10); XCTAssertEqual(t.positions(at: 12).first?.changes, 1)
    }
    func testBackwardsJitterAndInvalidJumpDoNotMoveVehicle() throws {
        let t = try tracker(); t.update([bus(136)], at: 0); t.update([bus(138)], at: 5)
        let valid = try XCTUnwrap(t.positions(at: 7).first)
        t.update([bus(136)], at: 10); XCTAssertEqual(t.positions(at: 12).first?.coordinate, valid.coordinate)
        t.update([bus(239)], at: 15); XCTAssertTrue(t.positions(at: 15).isEmpty); XCTAssertEqual(t.heldCount, 1)
    }
    func testBadObservationDoesNotEraseIdentityHistory() throws {
        let t = try tracker(); t.update([bus(136)], at: 0)
        t.update([.init(id: "100", x: 155, y: 200)], at: 5); XCTAssertTrue(t.positions(at: 5).isEmpty)
        t.update([bus(137)], at: 10); XCTAssertEqual(t.positions(at: 12).first?.changes, 1)
    }
    func testMissingAndStaleVehiclesAreRemoved() throws {
        let t = try tracker(); t.update([bus(136)], at: 0)
        XCTAssertTrue(t.positions(at: 20).isEmpty)
        t.update([], at: 5); XCTAssertTrue(t.positions(at: 5).isEmpty)
    }
    func testLapBoundaryContinuesForward() throws {
        let t = try tracker(), stops = t.route.stops
        let a = stops.last!.diagram, b = stops[0].diagram, c = stops[1].diagram
        t.update([.init(id: "1", x: a[0] + (b[0] - a[0]) * 0.96, y: a[1] + (b[1] - a[1]) * 0.96)], at: 0)
        let before = try XCTUnwrap(t.positions(at: 0).first)
        t.update([.init(id: "1", x: b[0] + (c[0] - b[0]) * 0.02, y: b[1] + (c[1] - b[1]) * 0.02)], at: 5)
        let after = try XCTUnwrap(t.positions(at: 7).first)
        XCTAssertEqual(after.changes, 1); XCTAssertLessThan(before.coordinate.distance(to: after.coordinate), 100)
    }
    func testSnapshotRejectsOtherRoutesAndStaleTimes() {
        let now = Date(), time = ISO8601DateFormatter().string(from: now)
        XCTAssertTrue(CircularFeed(routeId: "41946", checkedAt: time, vehicles: []).validated(at: now))
        XCTAssertFalse(CircularFeed(routeId: "41841", checkedAt: time, vehicles: []).validated(at: now))
        XCTAssertFalse(CircularFeed(routeId: "41946", checkedAt: time, vehicles: []).validated(at: now.addingTimeInterval(21)))
    }
    func testQuestAcceptanceIsExclusiveInSession() throws {
        var session = QuestSession(); let quest = try XCTUnwrap(Quest.demo.first { $0.mode == .firstCome })
        XCTAssertTrue(session.accept(quest)); XCTAssertFalse(session.accept(quest)); XCTAssertEqual(session.progress[quest.id], .accepted)
    }
    func testResultQuestValidatesTextAndCannotBeAcceptedAsSingleWorker() throws {
        var session = QuestSession(); let quest = try XCTUnwrap(Quest.demo.first { $0.mode == .resultReward })
        XCTAssertFalse(session.accept(quest)); XCTAssertFalse(session.submit(quest, text: "짧음"))
        XCTAssertTrue(session.submit(quest, text: "중앙도서관 안내데스크에서 발견했어요"))
        XCTAssertFalse(session.submit(quest, text: "중앙도서관 안내데스크에서 발견했어요"))
    }
    func testZoomSeparatesQuestMarkersWithoutDroppingQuests() {
        let groups = QuestMapGroup.groups(Quest.demo, zoom: 16)
        XCTAssertEqual(groups.flatMap(\.quests).map(\.id).sorted(), Quest.demo.map(\.id).sorted())
        XCTAssertTrue(QuestMapGroup.groups(Quest.demo, zoom: 17).allSatisfy { $0.quests.count == 1 })
        XCTAssertTrue(Quest.demo.allSatisfy(\.isValid))
    }
}

final class FoundItemMapTests: XCTestCase {
    func testZoomKeepsEveryItemAndRevealsLocations() {
        let rows = (0..<12).map { i in FoundItemMapEntry(id: "item-\(i)", title: "물건", coordinate: .init(latitude: 37.461 + Double(i) * 0.0001, longitude: 126.951), isCenter: false) }
        let coarse = FoundItemMapGroup.groups(rows, zoom: 13)
        let detail = FoundItemMapGroup.groups(rows, zoom: 20)
        XCTAssertEqual(Set(coarse.flatMap { $0.entries.map(\.id) }), Set(rows.map(\.id)))
        XCTAssertEqual(detail.count, rows.count)
        XCTAssertLessThan(coarse.count, detail.count)
    }
    func testSameLocationPreservesCountAndCentersRemainIndependent() {
        let geo = CampusCoordinate(latitude: 37.46, longitude: 126.95)
        let rows = [FoundItemMapEntry(id: "center", title: "센터", coordinate: geo, isCenter: true), .init(id: "a", title: "지갑", coordinate: geo, isCenter: false), .init(id: "b", title: "우산", coordinate: geo, isCenter: false)]
        let groups = FoundItemMapGroup.groups(rows, zoom: 20)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.filter { !$0.isCenter }.first?.entries.count, 2)
        XCTAssertTrue(FoundItemMapGroup.groups([.init(id: "bad", title: "", coordinate: .init(latitude: .nan, longitude: 0), isCenter: false)], zoom: 14).isEmpty)
    }
}
