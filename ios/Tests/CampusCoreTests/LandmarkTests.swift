import XCTest
@testable import CampusCore

final class LandmarkTests: XCTestCase {
    func testNearestRespectsRadiusAndCollected() throws {
        let jahayeon = try XCTUnwrap(Landmark.all.first { $0.id == "jahayeon" }).coordinate
        let near = CampusCoordinate(latitude: jahayeon.latitude + 0.0002, longitude: jahayeon.longitude) // ~22m
        XCTAssertEqual(Landmark.nearest(to: near)?.id, "jahayeon")
        XCTAssertNil(Landmark.nearest(to: near, excluding: ["jahayeon"]))
        let far = CampusCoordinate(latitude: jahayeon.latitude + 0.001, longitude: jahayeon.longitude)     // ~111m
        XCTAssertNil(Landmark.nearest(to: far))
        XCTAssertNil(Landmark.nearest(to: .init(latitude: .nan, longitude: 0)))
    }

    func testIDsUniqueAndCoordinatesValid() {
        XCTAssertEqual(Set(Landmark.all.map(\.id)).count, Landmark.all.count)
        XCTAssertTrue(Landmark.all.allSatisfy(\.coordinate.isValid))
    }
}
