import XCTest
@testable import CampusCore

final class PlaceDirectoryTests: XCTestCase {
    func testBundledCatalogAndStableIdentity() throws {
        XCTAssertEqual(CampusBuildingCatalog.all.count, 251)
        XCTAssertEqual(Set(CampusBuildingCatalog.all.map(\.id)).count, 251)
        XCTAssertEqual(CampusBuildingCatalog.all.compactMap(\.details).count, 251)
        XCTAssertEqual(CampusBuildingCatalog.all.reduce(0) { $0 + ($1.details?.facilities.count ?? 0) }, 646)
        let building = try XCTUnwrap(CampusBuildingCatalog.search("301").first)
        XCTAssertEqual(building.number, "301")
        XCTAssertTrue(building.coordinate.isValid)
        XCTAssertEqual(building.directionsURL?.host, "map.kakao.com")
    }

    func testSearchFindsFacilitiesAndEnglishNames() {
        XCTAssertFalse(CampusBuildingCatalog.search("파스쿠치").isEmpty)
        let english = CampusBuildingCatalog.all.first { !($0.details?.englishName ?? "").isEmpty }!
        XCTAssertTrue(CampusBuildingCatalog.search(english.details!.englishName!).contains { $0.id == english.id })
    }

    func testOnlyVerifiedBuildingJoinsAreExposed() {
        XCTAssertEqual(PlaceDirectory.labs.count, 32)
        XCTAssertEqual(PlaceDirectory.venues.count, 7)
        XCTAssertEqual(Set(PlaceDirectory.labs.map(\.buildingNumber)), ["138", "301", "302"])
        XCTAssertFalse(PlaceDirectory.labs.contains { $0.buildingNumber == "303" })
        let numbers = Set(CampusBuildingCatalog.all.compactMap(\.number))
        XCTAssertTrue(PlaceDirectory.venues.allSatisfy { numbers.contains($0.buildingNumber) })
    }

    func testFloorSortAndUnknownFloors() {
        XCTAssertLessThan(PlaceDirectory.floorOrder("지하2층"), PlaceDirectory.floorOrder("지하1층"))
        XCTAssertLessThan(PlaceDirectory.floorOrder("지상2층"), PlaceDirectory.floorOrder("지상10층"))
        XCTAssertEqual(PlaceDirectory.floorName(nil), "층 정보 미등록")
        XCTAssertEqual(PlaceDirectory.floorOrder("미등록"), Int.max)
        XCTAssertEqual(PlaceDirectory.floorOrder("지상9999999999999999999999999999층"), Int.max)
    }

    func testProfessorTopicAndCrossFloorSearchUsesVisibleContent() throws {
        let building = try XCTUnwrap(CampusBuildingCatalog.all.first { $0.number == "301" })
        let labs = PlaceDirectory.labs(in: building)
        let lab = try XCTUnwrap(labs.first { $0.professor == "강유" })
        XCTAssertEqual(lab.floor, "지상5층")
        XCTAssertTrue(PlaceDirectory.matches("강유 그래프", fields: lab.searchFields))
        XCTAssertTrue(PlaceDirectory.matches("데이터마이닝", fields: lab.searchFields))
        XCTAssertFalse(PlaceDirectory.matches("2026-11-23", fields: lab.searchFields))
        XCTAssertFalse(PlaceDirectory.matches("https", fields: lab.searchFields))
        XCTAssertFalse(PlaceDirectory.matches("강유 로봇", fields: lab.searchFields))
        XCTAssertTrue(PlaceDirectory.floors(in: building).contains(lab.floor))
    }

    func testCafeAliasesMenusAndUnknownPrices() throws {
        let venue = try XCTUnwrap(PlaceDirectory.venues.first { $0.id == "cafe-111" })
        XCTAssertTrue(PlaceDirectory.matches("파스쿠치", fields: venue.searchFields))
        XCTAssertTrue(PlaceDirectory.matches("111 라떼", fields: venue.searchFields))
        XCTAssertFalse(PlaceDirectory.matches("2026", fields: venue.searchFields))
        XCTAssertEqual(venue.featuredMenu?.name, "바닐라빈 골든라떼")
        XCTAssertTrue(venue.menus.allSatisfy { $0.priceWon == nil })
        XCTAssertEqual(venue.menus.first?.priceLabel, "가격은 매장에서 확인")
        XCTAssertTrue(venue.menus.allSatisfy { PlaceDirectory.imageName($0.photoAsset) != nil && $0.photoCredit != nil })
    }

    func testDessertCollageIsNotMisrepresentedAsIndividualProduct() throws {
        let venue = try XCTUnwrap(PlaceDirectory.venues.first { $0.id == "cafe-109" })
        XCTAssertNotNil(venue.photoAsset)
        XCTAssertEqual(venue.photoCaption, "카페109 디저트 모음")
        XCTAssertNil(venue.featuredMenu)
        XCTAssertTrue(venue.menus.allSatisfy { $0.photoAsset == nil })
    }

    func testSourceAndAssetPathsAreBounded() {
        XCTAssertNil(PlaceDirectory.imageName("https://example.com/image.png"))
        XCTAssertNil(PlaceDirectory.imageName("menu_photos/../other.png"))
        XCTAssertEqual(PlaceDirectory.imageName("menu_photos/pascucci-latte.png"), "PlaceMenu-pascucci-latte")
        XCTAssertNil(PlaceDirectory.sourceURL("javascript:alert(1)"))
        XCTAssertNil(PlaceDirectory.phoneURL("미등록"))
        XCTAssertEqual(PlaceDirectory.phoneURL("(02) 880-7263")?.absoluteString, "tel:028807263")
    }
}
