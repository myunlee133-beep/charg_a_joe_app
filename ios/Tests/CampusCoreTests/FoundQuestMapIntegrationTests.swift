import XCTest
@testable import CampusCore

final class FoundQuestMapIntegrationTests: XCTestCase {
    func testQuestLabelAvoidsFoundItemCountWithoutChangingInventory() throws {
        let location = CampusCoordinate(latitude: 37.46328, longitude: 126.95015)
        let entries = (0..<34).map {
            FoundItemMapEntry(id: "found:\($0)", title: "분실물", coordinate: location, isCenter: false)
        }
        let group = try XCTUnwrap(FoundItemMapGroup.groups(entries, zoom: 17).first)
        let countBadge = CGRect(x: 160, y: 200, width: 90, height: 34)
        let quest = MapMarkerFootprint(id: "quest", anchor: CGPoint(x: 205, y: 217),
            size: CGSize(width: 144, height: 66), anchorY: 0.5)
        let placed = MapMarkerLayout.place([quest], avoiding: [countBadge],
            in: CGRect(x: 0, y: 0, width: 400, height: 800))
        let label = try XCTUnwrap(placed[quest.id])
        XCTAssertFalse(label.frame.intersects(countBadge))
        XCTAssertEqual(group.entries.count, 34)
        XCTAssertLessThan(group.coordinate.distance(to: location), 0.001)
        XCTAssertTrue(FoundItemMapSelection(group: group).contains(latitude: location.latitude, longitude: location.longitude))
    }
}
