import XCTest
@testable import CampusCore

final class CampusAmenitiesTests: XCTestCase {
    func testFacilitiesKeepIdentityAndVerifiedBuildingLocation() {
        XCTAssertEqual(CampusAmenities.all.count, 646)
        XCTAssertEqual(Set(CampusAmenities.all.map(\.id)).count, 646)
        XCTAssertEqual(CampusAmenities.all.filter { $0.kind == .pharmacy }.count, 1)
        XCTAssertEqual(CampusAmenities.all.filter { $0.kind == .convenience }.count, 17)
        XCTAssertEqual(CampusAmenities.all.filter { $0.kind == .cafe }.count, 28)
        XCTAssertTrue(CampusAmenities.all.allSatisfy { $0.building.coordinate.isValid && $0.building.details!.facilities.contains($0.facility) })
    }

    func testPharmacyHasOfficialContactAndHoursWithoutInventingWeekendHours() throws {
        let pharmacy = try XCTUnwrap(CampusAmenities.search("약국").first)
        XCTAssertEqual(pharmacy.id, "snu-amenity-196")
        XCTAssertEqual(pharmacy.building.number, "63")
        XCTAssertEqual(pharmacy.shortFloor, "2층")
        XCTAssertEqual(pharmacy.phone, "02-880-6792")
        XCTAssertEqual(pharmacy.weekdayHours, "09:00–18:10")
        XCTAssertNil(pharmacy.info?.saturdayHours)
        XCTAssertTrue(pharmacy.sourceURL.hasPrefix("https://www.snu.ac.kr/"))
    }

    func testConvenienceSearchDoesNotReturnUnrelatedEnglishBuildingNames() {
        let results = CampusAmenities.search("ＣＵ")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.facility.name == "CU" })
        XCTAssertTrue(CampusBuildingCatalog.search("CU", includeFacilityNames: false).allSatisfy {
            PlaceDirectory.matches("CU", fields: [$0.name, $0.details?.englishName ?? ""])
        })
        XCTAssertEqual(CampusAmenities.search("63 약국").map(\.id), ["snu-amenity-196"])
        XCTAssertTrue(CampusAmenities.search("없는시설908abc").isEmpty)
        XCTAssertTrue(CampusAmenities.search("   ").isEmpty)
    }

    func testCafeJoinsUseNamesAndAliasesRatherThanOnlyBuildingNumber() throws {
        let hall = try XCTUnwrap(CampusBuildingCatalog.all.first { $0.number == "63" })
        let cafes = CampusAmenities.inBuilding(hall, kind: .cafe)
        XCTAssertEqual(cafes.count, 2)
        XCTAssertEqual(cafes.first { $0.facility.name == "라운지스낵" }?.venue?.id, "cafe-63")
        XCTAssertNil(cafes.first { $0.facility.name == "Flu id" }?.venue)
        let cafe109 = try XCTUnwrap(CampusAmenities.all.first { $0.id == "snu-amenity-79" })
        XCTAssertEqual(cafe109.name, "카페109 by 스누코스")
        XCTAssertEqual(cafe109.shortFloor, "1층")
    }

    func testMapGroupsNeverInventDistinctStorefrontCoordinates() {
        let groups = CampusAmenities.mapGroups()
        XCTAssertEqual(groups.flatMap(\.amenities).count, 46)
        XCTAssertEqual(Set(groups.map(\.id)).count, groups.count)
        XCTAssertTrue(groups.allSatisfy { group in group.amenities.allSatisfy { $0.building.id == group.id && CampusAmenityKind.everyday.contains($0.kind) } })
        XCTAssertEqual(CampusAmenities.mapGroups(kind: .pharmacy).map(\.building.number), ["63"])
    }

    func testSupplementJoinAndSourceURLsAreValid() throws {
        XCTAssertEqual(CampusAmenities.information.count, 10)
        XCTAssertEqual(Set(CampusAmenities.information.map(\.facilityID)).count, 10)
        for info in CampusAmenities.information {
            let amenity = try XCTUnwrap(CampusAmenities.all.first { $0.id == info.facilityID })
            XCTAssertEqual(amenity.building.number, info.buildingNumber)
            XCTAssertNotNil(PlaceDirectory.sourceURL(info.sourceURL))
            XCTAssertNotNil(info.phone.flatMap(PlaceDirectory.phoneURL))
        }
    }
}
