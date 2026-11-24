import Foundation

enum PlaceResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    static func decode<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let url = bundle.url(forResource: name, withExtension: "json") else { return nil }
        do { return try JSONDecoder().decode(type, from: Data(contentsOf: url)) }
        catch { print("PlaceResources: could not load \(name): \(error)"); return nil }
    }
}

struct ResearchLab: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let buildingNumber: String
    let room: String
    let rooms: [String]
    let floor: String
    let floorDerived: Bool
    let professor: String
    let professorURL: String
    let phone: String
    let url: String
    let checkedAt: String
    let topics: [String]
    let field: String
    let summary: String

    var searchFields: [String] { [name, professor, field, summary, room] + topics }
}

struct CampusVenue: Codable, Hashable, Identifiable {
    let id: String
    let buildingNumber: String
    let name: String
    let aliases: [String]
    let category: String
    let floor: String
    let phone: String
    let weekdayHours: String
    let checkedAt: String
    let sourceURL: String
    let menuSourceURL: String
    let menuNote: String
    let menus: [VenueMenu]
    let photoAsset: String?
    let photoSourceURL: String?
    let photoCaption: String?
    let photoCredit: String?

    var featuredMenu: VenueMenu? { menus.first { $0.featured == true } }
    var searchFields: [String] { [name, buildingNumber, buildingNumber + "동"] + aliases + menus.map(\.name) }
}

struct VenueMenu: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    let category: String
    let description: String
    let priceWon: Int?
    let photoAsset: String?
    let photoSourceURL: String?
    let photoCredit: String?
    let featured: Bool?

    var priceLabel: String { priceWon.map { "\($0.formatted())원" } ?? "가격은 매장에서 확인" }
}

enum PlaceDirectory {
    private struct LabFile: Decodable { let labs: [ResearchLab] }
    private struct VenueFile: Decodable { let venues: [CampusVenue] }
    // Join only by a registered building number, never by a guessed coordinate.
    static let labs: [ResearchLab] = {
        let numbers = Set(CampusBuildingCatalog.all.compactMap(\.number))
        return (PlaceResources.decode("research_labs", as: LabFile.self)?.labs ?? [])
            .filter { numbers.contains($0.buildingNumber) }
    }()
    static let venues: [CampusVenue] = {
        let numbers = Set(CampusBuildingCatalog.all.compactMap(\.number))
        return (PlaceResources.decode("campus_venues", as: VenueFile.self)?.venues ?? [])
            .filter { numbers.contains($0.buildingNumber) }
    }()

    static func labs(in building: CampusBuilding) -> [ResearchLab] {
        labs.filter { $0.buildingNumber == building.number }
    }
    static func venues(in building: CampusBuilding) -> [CampusVenue] {
        venues.filter { $0.buildingNumber == building.number }
    }
    static func floors(in building: CampusBuilding) -> [String] {
        let values = (building.details?.facilities.map { floorName($0.floor) } ?? [])
            + labs(in: building).map(\.floor) + venues(in: building).map(\.floor)
        return Set(values).sorted { lhs, rhs in
            let a = floorOrder(lhs), b = floorOrder(rhs)
            return a == b ? lhs.localizedStandardCompare(rhs) == .orderedAscending : a < b
        }
    }
    static func floorName(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "층 정보 미등록" }
        return value
    }
    static func floorOrder(_ floor: String) -> Int {
        guard let n = Int(floor.filter(\.isNumber)) else { return Int.max }
        return floor.contains("지하") || floor.uppercased().hasPrefix("B") ? -n : n
    }
    static func matches(_ query: String, fields: [String]) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace).map { normalized(String($0)) }
        let text = fields.map(normalized)
        return terms.allSatisfy { term in text.contains { $0.contains(term) } }
    }
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ko_KR"))
            .filter { !$0.isWhitespace }
    }
    static func phoneURL(_ phone: String) -> URL? {
        let digits = phone.filter(\.isNumber)
        guard (8...12).contains(digits.count) else { return nil }
        return URL(string: "tel:" + digits)
    }
    static func sourceURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    static func imageName(_ asset: String?) -> String? {
        guard let asset, asset.hasPrefix("menu_photos/"), !asset.contains("..") else { return nil }
        return "PlaceMenu-" + ((asset as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}
