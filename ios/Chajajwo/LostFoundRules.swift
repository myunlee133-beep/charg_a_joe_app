import Foundation

/// Shared client-side form checks. Supabase constraints independently validate writes.
enum LostFoundRules {
    static let policeReceiptNotice = "경찰서로 이관된 물품은 분실자가 실제로 수령했는지 앱에서 확인할 수 없습니다. 현재 보관·수령 가능 여부는 보관 중인 경찰서에 직접 확인해 주세요."
    static func registrantTitle(source: String) -> String {
        ["mysnu", "staff"].contains(source) ? "운영진" : "사용자"
    }
    static let maximumPhotoBytes = 512 * 1024
    static let maximumLocationCharacters = 120
    static let categories = ["지갑", "전자기기", "학생증", "우산", "의류", "가방", "열쇠", "기타"]
    static func validTitle(_ value: String) -> Bool { (2...100).contains(value.trimmingCharacters(in: .whitespacesAndNewlines).count) }
    static func validDescription(_ value: String, required: Bool) -> Bool {
        let n = value.trimmingCharacters(in: .whitespacesAndNewlines).count
        return (required ? 2...1000 : 0...1000).contains(n)
    }
    static func validProof(_ value: String) -> Bool {
        (10...500).contains(value.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }
    static func validLocation(_ value: String) -> Bool {
        (2...maximumLocationCharacters).contains(locationCharacterCount(value))
    }
    static func locationCharacterCount(_ value: String) -> Int {
        // PostgreSQL char_length counts Unicode scalars, not composed graphemes.
        value.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }
    static func locationName(buildingTitle: String?, detail: String, direct: Bool) -> String? {
        let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return nil }
        if direct { return detail }
        guard let buildingTitle else { return nil }
        return "\(buildingTitle) · \(detail)"
    }
    static func validPhoto(_ data: Data?) -> Bool {
        guard let data else { return true }
        return data.count >= 3 && data.count <= maximumPhotoBytes && data.starts(with: [0xff, 0xd8, 0xff])
    }
    static func validCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && (33...39).contains(latitude) && (124...132).contains(longitude)
    }
    static func validCampusCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && (37.4...37.51).contains(latitude) && (126.9...127.0).contains(longitude)
    }
    static func validEventDate(_ date: Date, now: Date = Date()) -> Bool { date <= now.addingTimeInterval(300) }
}

/// Current custody location, independent of who registered or found the item.
enum LostFoundStorage: String, CaseIterable, Identifiable {
    case center101 = "101동 분실물센터"
    case center67 = "67동 두레문예관"
    case shuttle = "셔틀버스 분실물 보관소"
    case other = "기타"
    case police = "관악경찰서"
    var id: String { rawValue }

    static func classify(location: String, status: String) -> Self {
        let name = location.replacingOccurrences(of: " ", with: "")
        if name.contains("관악경찰서") { return .police }
        // An unknown police destination must not be labeled as Gwanak or a campus center.
        if status == "police" { return .other }
        if name.range(of: "(?<![0-9])101동", options: .regularExpression) != nil || name.contains("아시아연구소") { return .center101 }
        if name.range(of: "(?<![0-9])67동", options: .regularExpression) != nil || name.contains("두레문예관") || name.contains("두레학생문예관") { return .center67 }
        if name.range(of: "(?<![0-9])331동", options: .regularExpression) != nil || name.contains("차량고") || name.contains("차량정비고") || name.contains("셔틀버스분실물보관소") { return .shuttle }
        return .other
    }
}
