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
    let clue: String          // 미발견일 때 보여주는 단서 (도감·AR)
    let blurb: String         // 발견 후 설명

    /// AR Resource Group `TreasureTargets` 안의 대상 사진 이름. 보물 id와 같다.
    var targetImage: String { id }

    /// GPS 오차(도심·건물 옆 10~30m)를 감안한 반경. 이 안에 들어오면 지도에 여우가 나타난다.
    static let collectRadius: Double = 50

    // ponytail: 좌표는 건물 데이터/지도에서 잡은 값. 블루포트=915동, 기숙사 라커=900동.
    static let all: [Landmark] = [
        .init(id: "fox", name: "탐험 여우", place: "정문", grade: .common, art: "Treasure-fox",
              coordinate: .init(latitude: 37.46630, longitude: 126.94835),
              clue: "한 번쯤 사진을 찍지 않았을까?",
              blurb: "서울대의 첫인상, 정문 앞을 지키던 탐험 여우. 이제 함께 캠퍼스를 누벼요."),
        .init(id: "key", name: "숨겨진 열쇠", place: "자하연", grade: .common, art: "Treasure-key",
              coordinate: .init(latitude: 37.46109, longitude: 126.95380),
              clue: "꽥꽥꽥",
              blurb: "자하연 오리가 물고 있던 열쇠. 무엇을 여는 열쇠일까요?"),
        .init(id: "doraji", name: "도라지", place: "중앙도서관", grade: .rare, art: "Treasure-doraji",
              coordinate: .init(latitude: 37.45940, longitude: 126.95199),
              clue: "도라지",
              blurb: "중앙도서관 어딘가에서 자라난 도라지. 책 냄새를 좋아해요."),
        .init(id: "ghost", name: "공학 유령", place: "붉은 광장", grade: .common, art: "Treasure-ghost",
              coordinate: .init(latitude: 37.45587, longitude: 126.95123),
              clue: "하나의 유령이 공대를 배회하고 있다.",
              blurb: "아랫공대 붉은 광장을 떠도는 유령. 생각보다 친절해요."),
        .init(id: "reed", name: "갈댓닢", place: "하늘 정원", grade: .rare, art: "Treasure-reed",
              coordinate: .init(latitude: 37.45903, longitude: 126.95247),
              clue: "슬슬 추워지는 거 같아",
              blurb: "하늘 정원 바람에 흔들리던 갈댓잎 한 장."),
        .init(id: "sombrero", name: "하얀 솜브레로", place: "셔틀 승차장", grade: .rare, art: "Treasure-sombrero",
              coordinate: .init(latitude: 37.46590, longitude: 126.94890),
              clue: "¡vamos todos! 출발할 시간이야",
              blurb: "셔틀 승차장에 누가 두고 간 하얀 솜브레로."),
        .init(id: "teapot", name: "파란 주전자", place: "블루포트", grade: .legendary, art: "Treasure-teapot",
              coordinate: .init(latitude: 37.465012, longitude: 126.957503),
              clue: "커피를 디자인하다",
              blurb: "블루포트의 파란 주전자. 커피 향이 아직 남아 있어요."),
        .init(id: "bear", name: "공대곰돌이", place: "39동", grade: .legendary, art: "Treasure-bear",
              coordinate: .init(latitude: 37.45465, longitude: 126.95157),
              clue: "문 좀 닫아줘…",
              blurb: "39동 문 앞을 지키는 공대곰돌이. 문은 꼭 닫아 주세요."),
        .init(id: "trophy", name: "마이너 트로피", place: "기숙사 라커", grade: .legendary, art: "Treasure-trophy",
              coordinate: .init(latitude: 37.46149, longitude: 126.95810),
              clue: "어쩌다 관악사는 강팀이 되었는가",
              blurb: "기숙사 라커에 잠들어 있던 관악사의 트로피."),
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
