import Foundation

/// Geographic points from the October 2026 SNU campus-map snapshot, plus two separately
/// attributed OSM building records. This is a local, offline catalog; no network needed.
struct CampusBuilding: Codable, Identifiable, Hashable {
    let id: String
    let number: String?
    let name: String
    let latitude: Double
    let longitude: Double
    let source: String
    let details: CampusBuildingDetails?

    var buildingNumberLabel: String {
        guard let number, !number.isEmpty else { return "캠퍼스 장소" }
        return number + "동"
    }

    var displayTitle: String { number == nil ? name : "\(buildingNumberLabel) · \(name)" }

    var coordinate: CampusCoordinate { .init(latitude: latitude, longitude: longitude) }

    var mapURL: URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ",/?#")
        let encoded = displayTitle.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
        return URL(string: "https://map.kakao.com/link/map/\(encoded),\(latitude),\(longitude)")
    }

    var directionsURL: URL? {
        DirectionsURL.destination(name: name, latitude: latitude, longitude: longitude)
    }

    var directionsEndpoint: DirectionsEndpoint {
        .init(name: displayTitle, latitude: latitude, longitude: longitude)
    }
}

/// Official building information is bundled for offline use. Missing fields mean
/// the source did not publish that detail, rather than that a facility is absent.
struct CampusBuildingDetails: Codable, Hashable {
    let category: String
    let summary: String
    let englishName: String?
    let address: String?
    let phone: String?
    let website: String?
    let usage: String
    let facilities: [CampusBuildingFacility]
    let accessibility: [String]
    let notices: [CampusBuildingNotice]
    let sources: [CampusBuildingSource]
    let checkedAt: String

    var phoneURL: URL? {
        guard let phone,
              let range = phone.range(of: #"0\d{1,2}[- ]\d{3,4}[- ]\d{4}"#, options: .regularExpression) else { return nil }
        return URL(string: "tel:" + String(phone[range]).filter { $0.isNumber })
    }

    var websiteURL: URL? {
        guard let website, let url = URL(string: website), url.scheme == "https" else { return nil }
        return url
    }
}

struct CampusBuildingFacility: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let floor: String?
    let category: String
}

struct CampusBuildingNotice: Codable, Hashable {
    let title: String
    let body: String
    let sourceURL: URL
    let checkedAt: String
}

struct CampusBuildingSource: Codable, Hashable {
    let title: String
    let url: URL
    let checkedAt: String
}

enum CampusBuildingCatalog {
    static let all: [CampusBuilding] = load()

    static func load() -> [CampusBuilding] {
        guard let url = PlaceResources.bundle.url(forResource: "campus_buildings", withExtension: "json") else {
            print("CampusBuildingCatalog: campus_buildings.json is missing from the app bundle")
            return []
        }
        do {
            let items = try JSONDecoder().decode([CampusBuilding].self, from: Data(contentsOf: url))
            return items.filter {
                $0.latitude.isFinite && $0.longitude.isFinite &&
                (37.4...37.51).contains($0.latitude) && (126.9...127.0).contains($0.longitude)
            }
        } catch {
            print("CampusBuildingCatalog: failed to load catalog: \(error)")
            return []
        }
    }

    /// AND semantics over all space-delimited terms, matching numbers and names.
    /// No prefix or result-count limit is applied; return *every* matching building.
    static func search(_ query: String, among buildings: [CampusBuilding] = all) -> [CampusBuilding] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map { compact(String($0)) }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        return buildings.filter { building in
            let number = building.number ?? ""
            let facilityNames = building.details?.facilities.map(\.name) ?? []
            let fields = ([number, number + "동", building.name, building.details?.englishName ?? ""] + facilityNames).map(compact)
            return terms.allSatisfy { term in fields.contains { $0.contains(term) } }
        }.sorted { lhs, rhs in
            let queryKey = compact(query)
            let lhsExact = lhs.number.map { compact($0) == queryKey || compact($0 + "동") == queryKey } ?? false
            let rhsExact = rhs.number.map { compact($0) == queryKey || compact($0 + "동") == queryKey } ?? false
            if lhsExact != rhsExact { return lhsExact }
            if lhs.number == nil || rhs.number == nil {
                if (lhs.number == nil) != (rhs.number == nil) { return lhs.number != nil }
            }
            return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
    }

    /// Select only nearby building points. The map supplies a screen-sized hit
    /// radius, capped in metres so a tap on an empty road cannot select a distant building.
    static func nearest(latitude: Double, longitude: Double, within metres: Double,
                        among buildings: [CampusBuilding] = all) -> CampusBuilding? {
        guard latitude.isFinite, longitude.isFinite, metres.isFinite, metres >= 0 else { return nil }
        let radians = Double.pi / 180
        return buildings.compactMap { building -> (CampusBuilding, Double)? in
            let dy = (building.latitude - latitude) * radians
            let dx = (building.longitude - longitude) * radians * cos((building.latitude + latitude) / 2 * radians)
            let distance = 6_371_000 * hypot(dx, dy)
            return distance.isFinite && distance <= metres ? (building, distance) : nil
        }.min { $0.1 < $1.1 }?.0
    }

    private static func compact(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ko_KR"))
            .filter { !$0.isWhitespace }
    }
}
