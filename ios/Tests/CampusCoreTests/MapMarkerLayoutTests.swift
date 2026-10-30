import XCTest
@testable import CampusCore

final class MapMarkerLayoutTests: XCTestCase {
    let viewport = CGRect(x: 0, y: 0, width: 400, height: 800)
    func marker(_ id: String, x: CGFloat = 200, y: CGFloat = 350, width: CGFloat = 144, priority: Int = 0) -> MapMarkerFootprint {
        .init(id: id, anchor: CGPoint(x: x, y: y), size: CGSize(width: width, height: 66), anchorY: 60.0 / 66, priority: priority)
    }

    func testUnobstructedAndFilteredMarkersKeepTheirTrueAnchor() throws {
        let quest = marker("quest")
        let result = MapMarkerLayout.place([quest], avoiding: [], in: viewport)
        XCTAssertEqual(result[quest.id]?.offset, .zero)
        XCTAssertEqual(result[quest.id]?.frame, quest.frame)
        let restaurant = CGRect(x: 160, y: 330, width: 100, height: 56)
        XCTAssertNotEqual(MapMarkerLayout.place([quest], avoiding: [restaurant], in: viewport)[quest.id]?.offset, .zero)
        XCTAssertEqual(MapMarkerLayout.place([quest], avoiding: [], in: viewport)[quest.id]?.offset, .zero)
    }

    func testQuestAndRestaurantAtTheSameLocationRemainSeparated() throws {
        let quest = marker("quest")
        let restaurant = CGRect(x: 155, y: 335, width: 110, height: 54)
        let placement = try XCTUnwrap(MapMarkerLayout.place([quest], avoiding: [restaurant], in: viewport)[quest.id])
        XCTAssertFalse(placement.frame.intersects(restaurant.insetBy(dx: -MapMarkerLayout.gap, dy: -MapMarkerLayout.gap)))
        XCTAssertTrue(viewport.contains(placement.frame))
        XCTAssertEqual(quest.anchor, CGPoint(x: 200, y: 350))
        XCTAssertLessThan(hypot(placement.offset.x, placement.offset.y), 100)
    }

    func testSeveralQuestLabelsAvoidRestaurantsAndOneAnotherDeterministically() throws {
        let quests = [marker("b"), marker("a", priority: 1), marker("c", x: 210, y: 370)]
        let restaurants = [CGRect(x: 170, y: 330, width: 90, height: 54), CGRect(x: 80, y: 390, width: 90, height: 54)]
        let result = MapMarkerLayout.place(quests, avoiding: restaurants, in: viewport)
        let reversed = MapMarkerLayout.place(Array(quests.reversed()), avoiding: restaurants, in: viewport)
        XCTAssertEqual(result.count, quests.count)
        for quest in quests {
            let placement = try XCTUnwrap(result[quest.id])
            XCTAssertEqual(placement.offset, reversed[quest.id]?.offset)
            for restaurant in restaurants { XCTAssertFalse(placement.frame.intersects(restaurant)) }
            for other in quests where other.id != quest.id {
                XCTAssertFalse(placement.frame.intersects(try XCTUnwrap(result[other.id]).frame))
            }
        }
    }

    func testLargerZoomLabelAndViewportEdgeAreRecomputed() throws {
        let restaurant = CGRect(x: 160, y: 330, width: 90, height: 54)
        for width in [CGFloat(44), CGFloat(106), CGFloat(144)] {
            let quest = marker("quest", x: 200, y: 350, width: width)
            let placement = try XCTUnwrap(MapMarkerLayout.place([quest], avoiding: [restaurant], in: viewport)[quest.id])
            XCTAssertFalse(placement.frame.intersects(restaurant))
        }
        let edge = marker("edge", x: 30, y: 100)
        let placement = try XCTUnwrap(MapMarkerLayout.place([edge], avoiding: [CGRect(x: 0, y: 60, width: 80, height: 55)], in: viewport)[edge.id])
        XCTAssertTrue(viewport.contains(placement.frame))
    }

    func testOffscreenMarkersDoNotDisplaceVisibleMarkers() throws {
        let visible = marker("visible"), offscreen = marker("offscreen", x: -1000, y: -1000)
        let result = MapMarkerLayout.place([offscreen, visible], avoiding: [], in: viewport)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[visible.id]?.offset, .zero)
    }

    func testProjectionMatchesRotatedSdkSamplesAndRejectsDegenerateBasis() throws {
        let origin = CampusCoordinate(latitude: 37.46, longitude: 126.95)
        let horizontal = CampusCoordinate(latitude: 37.461, longitude: 126.95)
        let vertical = CampusCoordinate(latitude: 37.46, longitude: 126.951)
        let projection = try XCTUnwrap(CampusScreenProjection(center: CGPoint(x: 200, y: 400), origin: origin,
            horizontal: horizontal, vertical: vertical, span: 64))
        XCTAssertEqual(projection.point(for: horizontal).x, 264, accuracy: 0.001)
        XCTAssertEqual(projection.point(for: vertical).y, 464, accuracy: 0.001)
        XCTAssertEqual(projection.point(for: origin), CGPoint(x: 200, y: 400))
        XCTAssertNil(CampusScreenProjection(center: .zero, origin: origin, horizontal: origin, vertical: origin, span: 64))
    }
}
