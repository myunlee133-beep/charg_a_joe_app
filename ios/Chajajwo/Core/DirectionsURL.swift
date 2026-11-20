import Foundation

struct DirectionsEndpoint: Equatable {
    let name: String
    let latitude: Double
    let longitude: Double

    fileprivate var pathComponent: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        // Commas separate the name and coordinates; all other punctuation in a
        // building name must remain inside this one path component.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return "\(encoded),\(latitude),\(longitude)"
    }
}

enum DirectionsTransport: String, CaseIterable, Identifiable {
    case walk, traffic, car
    var id: String { rawValue }
    var title: String {
        switch self {
        case .walk: "도보"
        case .traffic: "대중교통"
        case .car: "자동차"
        }
    }
}

/// Kakao's documented web directions link, shared by every directions entry point.
enum DirectionsURL {
    static func destination(name: String, latitude: Double, longitude: Double) -> URL? {
        let endpoint = DirectionsEndpoint(name: name, latitude: latitude, longitude: longitude)
        guard let path = endpoint.pathComponent else { return nil }
        return URL(string: "https://map.kakao.com/link/to/\(path)")
    }

    static func route(from start: DirectionsEndpoint, to end: DirectionsEndpoint,
                      transport: DirectionsTransport = .walk) -> URL? {
        guard start.latitude != end.latitude || start.longitude != end.longitude,
              let startPath = start.pathComponent, let endPath = end.pathComponent else { return nil }
        return URL(string: "https://map.kakao.com/link/by/\(transport.rawValue)/\(startPath)/\(endPath)")
    }

    /// Only map web pages may navigate inside the directions browser. In particular,
    /// app schemes and App Store redirects must never leave the current app.
    static func inAppURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host?.lowercased(),
              host == "map.kakao.com" || host.hasSuffix(".map.kakao.com") ||
              host == "map.daum.net" || host.hasSuffix(".map.daum.net"),
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 || (scheme == "http" && url.port == 80),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "https"
        components.port = nil
        return components.url
    }
}
