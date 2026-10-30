import XCTest
@testable import CampusCore

final class FoundItemMapSelectionTests: XCTestCase {
    func testNumberSelectsEveryStorageLocationInTheCluster() {
        let a = CampusCoordinate(latitude: 37.46328, longitude: 126.95015)
        let b = CampusCoordinate(latitude: 37.46353, longitude: 126.94973)
        let group = FoundItemMapGroup(id: "cluster", entries: [
            .init(id: "a", title: "지갑", coordinate: a, isCenter: false),
            .init(id: "b", title: "우산", coordinate: a, isCenter: false),
            .init(id: "c", title: "열쇠", coordinate: b, isCenter: false)
        ])
        let selection = FoundItemMapSelection(group: group)
        XCTAssertEqual(selection.coordinates.count, 2)
        XCTAssertTrue(selection.contains(latitude: a.latitude, longitude: a.longitude))
        XCTAssertTrue(selection.contains(latitude: b.latitude, longitude: b.longitude))
        XCTAssertFalse(selection.contains(latitude: 37.47458, longitude: 126.95105))
    }

    func testRefreshUsesCurrentLocationInsteadOfFrozenItemIDs() {
        let location = CampusCoordinate(latitude: 37.46328, longitude: 126.95015)
        let selection = FoundItemMapSelection(id: "center", title: "101동", coordinate: location)
        // New arrivals at the same place match; an item moved to police no longer matches.
        let current = [location, location, CampusCoordinate(latitude: 37.47458, longitude: 126.95105)]
        XCTAssertEqual(current.filter { selection.contains(latitude: $0.latitude, longitude: $0.longitude) }.count, 2)
        XCTAssertFalse(selection.contains(latitude: .nan, longitude: 126.95015))
    }

    func testSameCoordinateNumberIncludesAll34ItemsAndNotCenters() {
        let a = CampusCoordinate(latitude: 37.46328, longitude: 126.95015)
        let b = CampusCoordinate(latitude: 37.47458392608702, longitude: 126.95105330444076)
        let rows = (0..<34).map { FoundItemMapEntry(id: "found:\($0)", title: "물품", coordinate: a, isCenter: false) }
            + (0..<24).map { FoundItemMapEntry(id: "police:\($0)", title: "이관", coordinate: b, isCenter: false) }
            + [.init(id: "center", title: "센터", coordinate: a, isCenter: true)]
        for zoom in 13...20 {
            let groups = FoundItemMapGroup.groups(rows, zoom: zoom).filter { !$0.isCenter }
            XCTAssertEqual(groups.reduce(0) { $0 + $1.entries.count }, 58)
            let selected = FoundItemMapSelection(group: groups.first { $0.entries.contains { $0.id == "found:0" } }!)
            XCTAssertEqual(rows.filter { !$0.isCenter && selected.contains(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }.count, 34)
        }
    }
}
