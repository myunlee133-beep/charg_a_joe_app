import XCTest
@testable import CampusCore

final class LandmarkTests: XCTestCase {
    func testNearbyRespectsRadiusAndCollected() throws {
        let jahayeon = try XCTUnwrap(Landmark.all.first { $0.id == "key" }).coordinate
        let near = CampusCoordinate(latitude: jahayeon.latitude + 0.0002, longitude: jahayeon.longitude) // ~22m
        XCTAssertEqual(Landmark.nearby(to: near).first?.id, "key")
        XCTAssertFalse(Landmark.nearby(to: near, excluding: ["key"]).contains { $0.id == "key" })
        let far = CampusCoordinate(latitude: jahayeon.latitude + 0.001, longitude: jahayeon.longitude)     // ~111m
        XCTAssertTrue(Landmark.nearby(to: far).isEmpty)
        XCTAssertTrue(Landmark.nearby(to: .init(latitude: .nan, longitude: 0)).isEmpty)
    }

    func testIDsUniqueAndCoordinatesValid() {
        XCTAssertEqual(Set(Landmark.all.map(\.id)).count, Landmark.all.count)
        XCTAssertTrue(Landmark.all.allSatisfy(\.coordinate.isValid))
    }
}
