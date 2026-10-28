import Foundation

/// Client-side convenience checks. The server independently enforces these limits.
enum CommunityRules {
    static func validNickname(_ value: String) -> Bool {
        value.range(of: "^[가-힣A-Za-z0-9_]{2,20}$", options: .regularExpression) != nil
    }

    static func validPost(title: String, body: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return (2...120).contains(t.count) && (2...10000).contains(b.count)
    }

    static func validComment(_ value: String) -> Bool {
        (1...2000).contains(value.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }

    static func validSourceURL(_ value: String) -> Bool {
        if value.isEmpty { return true }
        guard let url = URL(string: value), url.scheme == "https", let host = url.host,
              !host.isEmpty, !value.contains(where: { $0.isWhitespace }) else { return false }
        return true
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 30 && seen.insert($0).inserted }
            .prefix(5).map { $0 }
    }
}
