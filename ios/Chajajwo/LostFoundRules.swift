import Foundation

/// Shared client-side form checks. Supabase constraints independently validate writes.
enum LostFoundRules {
    static let maximumPhotoBytes = 512 * 1024
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
        (2...160).contains(value.trimmingCharacters(in: .whitespacesAndNewlines).count)
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
