import Foundation

// Compile with CampusBuildings.swift to exercise the exact app model and search seam.
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

guard CommandLine.arguments.count == 2 else { fatalError("Pass campus_buildings.json") }
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let buildings = try JSONDecoder().decode([CampusBuilding].self, from: data)
require(buildings.count >= 250, "The complete campus catalog must load")
require(Set(buildings.map(\.id)).count == buildings.count, "Duplicate building IDs")
for building in buildings {
    require(building.latitude.isFinite && building.longitude.isFinite, "Invalid coordinate")
    guard let details = building.details else { fatalError("Missing details for \(building.id)") }
    require(!details.summary.isEmpty && !details.usage.isEmpty, "Missing building description")
    require(!details.sources.isEmpty, "Missing official attribution")
    require(Set(details.facilities.map(\.id)).count == details.facilities.count, "Duplicate facility IDs")
    for source in details.sources {
        let host = source.url.host ?? ""
        require(source.url.scheme == "https" && (host == "snu.ac.kr" || host.hasSuffix(".snu.ac.kr")),
                "Source is not an official SNU HTTPS page")
        require(!source.checkedAt.isEmpty, "Missing source verification date")
    }
}

let studentHall = buildings.first { $0.number == "63" }!
require(studentHall.details!.facilities.contains { $0.name.contains("서점") && $0.floor == "지상2층" },
        "Student-hall bookstore and its verified floor are missing")
require(studentHall.details!.phoneURL?.scheme == "tel", "Published contact must support calling")
require(CampusBuildingCatalog.search("63동", among: buildings).first?.id == studentHall.id,
        "Exact building-number matches must remain first")
require(CampusBuildingCatalog.search("약국", among: buildings).contains { $0.id == studentHall.id },
        "Published facilities must be searchable")
require(CampusBuildingCatalog.search("STUDENT CENTER", among: buildings).contains { $0.id == studentHall.id },
        "English official building names must be searchable")
require(CampusBuildingCatalog.search("  ", among: buildings).isEmpty, "Empty query must not list the campus")
require(CampusBuildingCatalog.nearest(latitude: studentHall.latitude, longitude: studentHall.longitude,
                                     within: 1, among: buildings)?.id == studentHall.id,
        "A tap on the building point must select it")
require(CampusBuildingCatalog.nearest(latitude: 37.5, longitude: 126.9, within: 40, among: buildings) == nil,
        "Empty map space must not select a distant building")
require(CampusBuildingCatalog.nearest(latitude: .nan, longitude: 126.95, within: 40, among: buildings) == nil,
        "Invalid map coordinates must not select a building")
let legacy = Data(#"[{"id":"legacy","number":"1","name":"기존 건물","latitude":37.46,"longitude":126.95,"source":"snu-campus-map"}]"#.utf8)
let legacyBuildings = try JSONDecoder().decode([CampusBuilding].self, from: legacy)
require(legacyBuildings.first?.details == nil,
        "Legacy catalogs must remain decodable without the optional details")
let museum = buildings.first { $0.number == "70" }!
require(!museum.details!.notices.isEmpty, "Verified museum reopening notice is missing")
let dorm = buildings.first { $0.number == "901" }!
require(!dorm.name.contains("대학원"), "901 must not be presented as a graduate residence")
print("Building catalog checks passed: \(buildings.count) places, \(buildings.reduce(0) { $0 + ($1.details?.facilities.count ?? 0) }) facility entries.")
