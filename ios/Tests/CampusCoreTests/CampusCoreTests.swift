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
        let middle = try XCTUnwrap(t.positions(at: 7.5).first)
        let target = try XCTUnwrap(t.positions(at: 10).first)
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
        let valid = try XCTUnwrap(t.positions(at: 10).first)
        t.update([bus(136)], at: 10); XCTAssertEqual(t.positions(at: 12).first?.coordinate, valid.coordinate)
        t.update([bus(239)], at: 15); XCTAssertTrue(t.positions(at: 15).isEmpty); XCTAssertEqual(t.heldCount, 1)
    }
    func testContinuousFramesAcrossPollsWithoutJumpOrRewind() throws {
        let t = try tracker(); t.update([bus(136)], at: 0)
        t.update([bus(138)], at: 5)
        var previous = try XCTUnwrap(t.positions(at: 5).first).coordinate
        for frame in 1...200 {
            let now = 5 + Double(frame) * 0.05
            if frame == 100 {
                let before = try XCTUnwrap(t.positions(at: now).first).coordinate
                t.update([bus(140)], at: now)
                XCTAssertEqual(t.positions(at: now).first?.coordinate, before)
            }
            let point = try XCTUnwrap(t.positions(at: now).first).coordinate
            XCTAssertGreaterThan(previous.distance(to: point), 0.001, "frame \(frame) stalled")
            XCTAssertLessThan(previous.distance(to: point), 2, "frame \(frame) jumped")
            XCTAssertLessThan(point.latitude, previous.latitude, "frame \(frame) rewound")
            previous = point
        }
    }

    func testCoarseCheckpointsKeepMovingThroughRepeatedFeeds() throws {
        let t = try tracker(); t.update([bus(136)], at: 0)
        let origin = try XCTUnwrap(t.positions(at: 0).first).coordinate
        for at in stride(from: 5.0, to: 30.0, by: 5.0) { t.update([bus(136)], at: at) }
        t.update([bus(188)], at: 30)
        XCTAssertEqual(t.positions(at: 30).first?.coordinate, origin)
        var previous = origin
        for second in 31...60 {
            let now = Double(second)
            let before = try XCTUnwrap(t.positions(at: now).first).coordinate
            if second % 5 == 0 {
                t.update([bus(188)], at: now)
                XCTAssertEqual(t.positions(at: now).first?.coordinate, before)
            }
            XCTAssertGreaterThan(previous.distance(to: before), 1)
            XCTAssertLessThan(previous.distance(to: before), 20)
            previous = before
        }
        XCTAssertEqual(t.positions(at: 65).first?.coordinate, previous)
        XCTAssertEqual(t.positions(at: 65).first?.changes, 1)
        XCTAssertLessThan(previous.distance(to: t.route.stops[3].coordinate), 35)
        XCTAssertTrue(t.positions(at: 80).isEmpty)
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
