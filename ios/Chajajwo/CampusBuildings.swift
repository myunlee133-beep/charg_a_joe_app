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

    var buildingNumberLabel: String {
        guard let number, !number.isEmpty else { return "캠퍼스 장소" }
        return number + "동"
    }

    var displayTitle: String { number == nil ? name : "\(buildingNumberLabel) · \(name)" }

    var directionsURL: URL? {
        // Use the installed Kakao Map app / web link without storing its credentials.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ",")
        let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
        return URL(string: "https://map.kakao.com/link/to/\(encoded),\(latitude),\(longitude)")
    }
}

enum CampusBuildingCatalog {
    static let all: [CampusBuilding] = load()

    static func load() -> [CampusBuilding] {
        guard let url = Bundle.main.url(forResource: "campus_buildings", withExtension: "json") else {
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
            let fields = [compact(number), compact(number + "동"), compact(building.name)]
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

    private static func compact(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ko_KR"))
            .filter { !$0.isWhitespace }
    }
}
