import Foundation

enum QuestMode: String, CaseIterable, Identifiable, Codable {
    case firstCome, resultReward
    var id: String { rawValue }
    var title: String { self == .firstCome ? "선착순 1명" : "결과 보상" }
}
enum QuestCategory: String, CaseIterable, Identifiable, Codable {
    case printDelivery, lost, errand
    var id: String { rawValue }
    var title: String { switch self { case .printDelivery: "인쇄·전달"; case .lost: "분실물 찾기"; case .errand: "심부름" } }
    var symbol: String { switch self { case .printDelivery: "printer"; case .lost: "binoculars"; case .errand: "shippingbox" } }
}
enum QuestProgress: String { case available, accepted, resultPending }
struct Quest: Identifiable, Codable {
    var id: String
    var title: String
    var category: QuestCategory
    var mode: QuestMode
    var reward: Int
    var place: String
    var building: String
    var coordinate: CampusCoordinate
    var distance: Int
    var details: String
    var requester: String
    var participants: Int = 0
    var rewardText: String { reward.formatted(.number.locale(Locale(identifier: "ko_KR"))) + "원" }
    var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reward > 0 && reward <= 1_000_000 && coordinate.isValid }
    static let demo: [Self] = [
        .init(id: "q1", title: "자료 프린트해서 16동에 가져다주세요", category: .printDelivery, mode: .firstCome, reward: 3000, place: "사회과학대학", building: "16동 · 1층 로비", coordinate: .init(latitude: 37.46056, longitude: 126.95142), distance: 120, details: "수업 자료를 A4 단면 흑백으로 12장 출력해서 가져다주세요. 16동 1층 로비에서 받을게요. 인쇄비는 보상과 별도로 드릴게요.", requester: "관악의 오후"),
        .init(id: "q2", title: "중앙도서관에서 에어팟을 잃어버렸어요", category: .lost, mode: .resultReward, reward: 20000, place: "중앙도서관", building: "62동 · 중앙도서관 주변", coordinate: .init(latitude: 37.45982, longitude: 126.95205), distance: 240, details: "흰색 에어팟 프로 케이스를 찾고 있어요. 파란 고래 키링이 달려 있어요. 발견 위치와 특징을 보내주세요.", requester: "도서관지박령", participants: 4),
        .init(id: "q3", title: "학생회관에서 택배 좀 받아주세요", category: .errand, mode: .firstCome, reward: 5000, place: "학생회관", building: "63동 · 1층 정문", coordinate: .init(latitude: 37.45925, longitude: 126.9506), distance: 310, details: "학생회관 앞에 도착하는 작은 택배를 대신 받아주세요. 한 손으로 들 수 있는 작은 상자예요.", requester: "느티나무"),
        .init(id: "q4", title: "분실한 검정 카드지갑을 찾습니다", category: .lost, mode: .resultReward, reward: 15000, place: "자하연", building: "자하연 · 산책로 주변", coordinate: .init(latitude: 37.46109, longitude: 126.9538), distance: 430, details: "자하연 주변에서 검정 카드지갑을 잃어버렸어요. 발견 위치와 특징을 알려주세요.", requester: "초록연못", participants: 2),
        .init(id: "q5", title: "과제 제본물을 공대까지 전달해주세요", category: .printDelivery, mode: .firstCome, reward: 7000, place: "신공학관", building: "301동 · 1층 로비", coordinate: .init(latitude: 37.4526, longitude: 126.9521), distance: 850, details: "학생회관 인쇄소에서 제본물을 수령해서 301동 로비로 가져다주세요.", requester: "공대가는길"),
        .init(id: "q6", title: "경영대에 두고 온 우산 가져다주세요", category: .errand, mode: .firstCome, reward: 4000, place: "경영대학", building: "58동 · 1층 라운지", coordinate: .init(latitude: 37.4645, longitude: 126.9532), distance: 610, details: "58동에 둔 남색 장우산을 학생회관으로 가져다주세요.", requester: "비오는관악")
    ]
}
struct QuestMapGroup: Identifiable {
    let id: String
    let quests: [Quest]
    var coordinate: CampusCoordinate {
        .init(latitude: quests.map(\.coordinate.latitude).reduce(0, +) / Double(quests.count),
              longitude: quests.map(\.coordinate.longitude).reduce(0, +) / Double(quests.count))
    }
    static func groups(_ quests: [Quest], zoom: Int) -> [Self] {
        if zoom >= 17 { return quests.map { .init(id: $0.id, quests: [$0]) } }
        let buckets = Dictionary(grouping: quests) { q in
            "\(Int(floor(q.coordinate.latitude / 0.003)))-\(Int(floor(q.coordinate.longitude / 0.003)))"
        }
        return buckets.keys.sorted().map { .init(id: $0, quests: buckets[$0]!.sorted { $0.id < $1.id }) }
    }
}

/// Session-local review state. This is not a multi-user acceptance/payment backend.
struct QuestSession {
    private(set) var progress: [String: QuestProgress] = [:]
    mutating func accept(_ quest: Quest) -> Bool {
        guard quest.mode == .firstCome, progress[quest.id] == nil else { return false }
        progress[quest.id] = .accepted; return true
    }
    mutating func submit(_ quest: Quest, text: String) -> Bool {
        guard quest.mode == .resultReward, progress[quest.id] == nil,
              text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 else { return false }
        progress[quest.id] = .resultPending; return true
    }
}


/// Clusters display coordinates without changing the stored item location.
struct FoundItemMapEntry {
    let id: String
    let title: String
    let coordinate: CampusCoordinate
    let isCenter: Bool
}
struct FoundItemMapGroup: Identifiable {
    let id: String
    let entries: [FoundItemMapEntry]
    var isCenter: Bool { entries.allSatisfy(\.isCenter) }
    var coordinate: CampusCoordinate {
        .init(latitude: entries.map { $0.coordinate.latitude }.reduce(0,+) / Double(entries.count),
              longitude: entries.map { $0.coordinate.longitude }.reduce(0,+) / Double(entries.count))
    }
    static func groups(_ entries: [FoundItemMapEntry], zoom: Int) -> [Self] {
        let valid = entries.filter { $0.coordinate.isValid }
        var result = valid.filter(\.isCenter).map { Self(id: $0.id, entries: [$0]) }
        let cells: [Double] = [0.024, 0.012, 0.006, 0.003, 0.0015, 0.0006, 0.00015]
        let cell = zoom >= 20 ? 0.0000001 : cells[max(0, min(cells.count - 1, zoom - 13))]
        let buckets = Dictionary(grouping: valid.filter { !$0.isCenter }) {
            "\(Int(floor($0.coordinate.latitude / cell)))-\(Int(floor($0.coordinate.longitude / cell)))"
        }
        for key in buckets.keys.sorted() {
            let rows = buckets[key]!.sorted { $0.id < $1.id }
            result.append(Self(id: rows.count == 1 ? rows[0].id : "found-cluster-\(zoom)-\(key)", entries: rows))
        }
        return result
    }
}

/// A map selection follows custody locations so refresh includes arrivals and excludes moved items.
struct FoundItemMapSelection: Identifiable {
    let id: String
    let title: String
    let coordinates: Set<CampusCoordinate>

    init(group: FoundItemMapGroup) {
        id = group.id
        title = "지도에서 선택한 분실물"
        coordinates = Set(group.entries.filter { !$0.isCenter && $0.coordinate.isValid }.map(\.coordinate))
    }

    init(id: String, title: String, coordinate: CampusCoordinate) {
        self.id = id; self.title = title
        coordinates = coordinate.isValid ? [coordinate] : []
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        let coordinate = CampusCoordinate(latitude: latitude, longitude: longitude)
        return coordinate.isValid && coordinates.contains(coordinate)
    }
}
