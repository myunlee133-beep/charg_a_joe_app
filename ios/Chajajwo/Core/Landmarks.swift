import Foundation

/// 보물 등급. 발견 방식은 모두 같고, 대상이 얼마나 숨어 있고 단서가 얼마나 모호한지로 나눈다.
enum TreasureGrade: String, CaseIterable, Identifiable {
    case common = "일반", rare = "희귀", legendary = "전설"
    var id: String { rawValue }
}

/// 캠퍼스에 숨은 보물(이스터 에그). 반경 안에 들어가면 지도에 여우가 나타나고,
/// AR 카메라로 `targetImage` 대상을 정확히 비추면 발견된다.
struct Landmark: Identifiable, Hashable {
    let id: String
    let name: String          // 보물 이름 (도감에 표시)
    let place: String         // 숨겨진 장소
    let grade: TreasureGrade
    let art: String           // 보물 일러스트 에셋 이름 (Treasure-*)
    let coordinate: CampusCoordinate
    let clue: String          // 미발견일 때 보여주는 단서 (도감 칸에는 짧은 `hint`)
    let hint: String
    let blurb: String         // 발견 후 설명

    /// AR Resource Group `TreasureTargets` 안의 대상 사진 이름. 보물 id와 같다.
    var targetImage: String { id }

    /// GPS 오차(도심·건물 옆 10~30m)를 감안한 반경. 이 안에 들어오면 지도에 여우가 나타난다.
    static let collectRadius: Double = 50

    // ponytail: 좌표·단서는 지도에서 대략 잡은 값. 현장에서 대상 사진을 찍으며 함께 맞춘다.
    static let all: [Landmark] = [
        .init(id: "gate", name: "첫걸음의 문", place: "정문", grade: .common, art: "Treasure-gate",
              coordinate: .init(latitude: 37.46630, longitude: 126.94835),
              clue: "모든 탐험은 여기서 시작돼요. ㄱ·ㅅ·ㄷ이 숨은 조형물을 정면에서 비춰보세요.",
              hint: "정문 어딘가",
              blurb: "'국립서울대학교'의 초성 ㄱ·ㅅ·ㄷ을 본뜬 정문에서 얻은 첫 보물."),
        .init(id: "jahayeon", name: "탐험 여우", place: "자하연", grade: .common, art: "Treasure-fox",
              coordinate: .init(latitude: 37.46109, longitude: 126.95380),
              clue: "인문대와 학생회관 사이 연못. 연못 이름이 적힌 안내판을 찾아보세요.",
              hint: "연못가",
              blurb: "자하연 연못가에서 졸고 있던 탐험 여우. 이제 함께 캠퍼스를 누벼요."),
        .init(id: "library", name: "비밀 책갈피", place: "중앙도서관", grade: .rare, art: "Treasure-bookmark",
              coordinate: .init(latitude: 37.45982, longitude: 126.95205),
              clue: "책이 가장 많은 건물. 창가 쪽 오래된 현판에 책갈피가 끼워져 있대요.",
              hint: "도서관 창가",
              blurb: "중앙도서관 창가 현판 뒤에 숨어 있던 책갈피."),
        .init(id: "democracy", name: "숨겨진 열쇠", place: "민주화 동상", grade: .rare, art: "Treasure-key",
              coordinate: .init(latitude: 37.46005, longitude: 126.95100),
              clue: "광장 어딘가, 이름들이 새겨진 돌판 아래 열쇠가 있어요.",
              hint: "광장 어딘가",
              blurb: "민주화를 위해 싸운 학생들을 기리는 동상 곁에서 찾은 열쇠."),
        .init(id: "waterfall", name: "숲의 도토리", place: "폭포", grade: .common, art: "Treasure-acorn",
              coordinate: .init(latitude: 37.45020, longitude: 126.95250),
              clue: "물소리를 따라 관악산 쪽으로. 폭포 앞 안내판을 비춰보세요.",
              hint: "물소리 나는 곳",
              blurb: "관악산 자락 폭포 옆 숲에서 굴러온 도토리."),
        .init(id: "observatory", name: "황금 잎사귀", place: "전망대", grade: .legendary, art: "Treasure-leaf",
              coordinate: .init(latitude: 37.44890, longitude: 126.95270),
              clue: "캠퍼스에서 가장 높은 곳, 서울이 내려다보이는 자리의 낡은 표지판.",
              hint: "오래된 나무 아래",
              blurb: "캠퍼스와 서울 시내가 한눈에 보이는 전망대에서만 얻을 수 있는 전설의 잎사귀."),
    ]

    /// `collected`에 없는 보물 중 반경 안에 있는 것들(가까운 순).
    static func nearby(to position: CampusCoordinate, excluding collected: Set<String> = [],
                       within radius: Double = collectRadius) -> [Landmark] {
        guard position.isValid else { return [] }
        return all
            .filter { !collected.contains($0.id) }
            .map { ($0, $0.coordinate.distance(to: position)) }
            .filter { $0.1 <= radius }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}
