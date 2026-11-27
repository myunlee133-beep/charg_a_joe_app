import Foundation

enum CampusAmenityKind: String, CaseIterable, Codable, Hashable {
    case pharmacy, convenience, cafe, food, bank, books, health, other

    var title: String {
        switch self {
        case .pharmacy: "약국"
        case .convenience: "편의점"
        case .cafe: "카페"
        case .food: "식당"
        case .bank: "은행·ATM"
        case .books: "서점·문구"
        case .health: "건강·의료"
        case .other: "기타 시설"
        }
    }
    var symbol: String {
        switch self {
        case .pharmacy: "cross.case.fill"
        case .convenience: "basket.fill"
        case .cafe: "cup.and.saucer.fill"
        case .food: "fork.knife"
        case .bank: "creditcard.fill"
        case .books: "books.vertical.fill"
        case .health: "heart.text.square.fill"
        case .other: "building.2.fill"
        }
    }
    static let everyday: [Self] = [.pharmacy, .convenience, .cafe]
    static let highlights: [Self] = [.pharmacy, .convenience, .cafe, .food]
    init(category: String) {
        switch category {
        case "약국": self = .pharmacy
        case "편의점": self = .convenience
        case "카페": self = .cafe
        case "식당", "채식식당": self = .food
        case "은행", "ATM": self = .bank
        case "서점", "문구", "기념품": self = .books
        case "건강", "병원": self = .health
        default: self = .other
        }
    }
}

struct CampusAmenityInfo: Codable, Hashable {
    let facilityID: String
    let buildingNumber: String
    let displayName: String?
    let aliases: [String]
    let phone: String?
    let weekdayHours: String?
    let saturdayHours: String?
    let holidayHours: String?
    let items: [String]
    let note: String?
    let sourceURL: String
    let checkedAt: String
}

/// Locations are building points, never inferred indoor or storefront coordinates.
struct CampusAmenity: Identifiable, Hashable {
    let building: CampusBuilding
    let facility: CampusBuildingFacility
    let info: CampusAmenityInfo?
    let venue: CampusVenue?

    var id: String { facility.id }
    var kind: CampusAmenityKind { .init(category: facility.category) }
    var name: String { info?.displayName ?? venue?.name ?? facility.name }
    var floor: String { venue?.floor ?? PlaceDirectory.floorName(facility.floor) }
    var shortFloor: String { floor.replacingOccurrences(of: "지상", with: "") }
    var location: String { building.name + " · " + building.buildingNumberLabel + " " + shortFloor }
    var phone: String? { info?.phone ?? venue?.phone }
    var weekdayHours: String? { info?.weekdayHours ?? venue?.weekdayHours }
    var sourceURL: String { info?.sourceURL ?? venue?.sourceURL ?? "https://map.snu.ac.kr/" }
    var checkedAt: String { info?.checkedAt ?? venue?.checkedAt ?? building.details?.checkedAt ?? "" }
    var searchFields: [String] {
        [name, facility.name, facility.category, kind.title, building.name, building.number ?? "", building.buildingNumberLabel, shortFloor]
            + (info?.aliases ?? []) + (venue?.aliases ?? [])
    }
}

struct CampusAmenityMapGroup: Identifiable {
    let building: CampusBuilding
    let amenities: [CampusAmenity]
    var id: String { building.id }
}

enum CampusAmenities {
    private struct InfoFile: Decodable { let facilities: [CampusAmenityInfo] }
    static let information: [CampusAmenityInfo] = PlaceResources.decode("campus_amenity_details", as: InfoFile.self)?.facilities ?? []

    static let all: [CampusAmenity] = {
        let supplements = Dictionary(Self.information.map { ($0.facilityID, $0) }, uniquingKeysWith: { first, _ in first })
        return CampusBuildingCatalog.all.flatMap { building in
            (building.details?.facilities ?? []).map { facility in
                let info = supplements[facility.id].flatMap { $0.buildingNumber == building.number ? $0 : nil }
                let venue = PlaceDirectory.venues(in: building).first { venue in
                    ([venue.name] + venue.aliases).contains { normalized($0) == normalized(facility.name) }
                }
                return CampusAmenity(building: building, facility: facility, info: info, venue: venue)
            }
        }
    }()

    static func inBuilding(_ building: CampusBuilding, kind: CampusAmenityKind? = nil) -> [CampusAmenity] {
        all.filter { $0.building.id == building.id && (kind == nil || $0.kind == kind) }.sorted(by: ordered)
    }

    static func search(_ query: String, kind: CampusAmenityKind? = nil) -> [CampusAmenity] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let key = normalized(query)
        return all.filter { (kind == nil || $0.kind == kind) && PlaceDirectory.matches(query, fields: $0.searchFields) }.sorted { lhs, rhs in
            let a = ([lhs.name, lhs.facility.name] + (lhs.info?.aliases ?? [])).contains { normalized($0) == key }
            let b = ([rhs.name, rhs.facility.name] + (rhs.info?.aliases ?? [])).contains { normalized($0) == key }
            return a == b ? ordered(lhs, rhs) : a
        }
    }

    static func mapGroups(kind: CampusAmenityKind? = nil) -> [CampusAmenityMapGroup] {
        let amenities = all.filter { amenity in kind == nil ? CampusAmenityKind.everyday.contains(amenity.kind) : amenity.kind == kind }
        return Dictionary(grouping: amenities, by: { $0.building.id }).values.compactMap { items in
            guard let first = items.first else { return nil }
            return CampusAmenityMapGroup(building: first.building, amenities: items.sorted(by: ordered))
        }.sorted { $0.building.displayTitle.localizedStandardCompare($1.building.displayTitle) == .orderedAscending }
    }

    private static func ordered(_ lhs: CampusAmenity, _ rhs: CampusAmenity) -> Bool {
        if lhs.building.id != rhs.building.id { return lhs.building.displayTitle.localizedStandardCompare(rhs.building.displayTitle) == .orderedAscending }
        let a = PlaceDirectory.floorOrder(lhs.floor), b = PlaceDirectory.floorOrder(rhs.floor)
        if a != b { return a < b }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ko_KR")).filter { !$0.isWhitespace }
    }
}
