import Foundation

/// AR로 수집하는 캠퍼스 랜드마크. 가까이(`collectRadius` 안) 가야 카메라로 잡을 수 있다.
struct Landmark: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String  // SF Symbol
    let coordinate: CampusCoordinate
    let blurb: String

    /// GPS 오차(도심·건물 옆 10~30m)를 감안한 수집 반경.
    static let collectRadius: Double = 50

    // ponytail: 좌표는 지도에서 대략 찍은 값. 현장에서 한 번씩 맞춰야 반경 판정이 정확하다.
    static let all: [Landmark] = [
        .init(id: "gate", name: "정문", symbol: "building.columns.fill",
              coordinate: .init(latitude: 37.46630, longitude: 126.94835),
              blurb: "'국립서울대학교'의 초성 ㄱ·ㅅ·ㄷ을 본뜬 서울대의 상징 조형물."),
        .init(id: "democracy", name: "민주화 동상", symbol: "figure.stand",
              coordinate: .init(latitude: 37.46005, longitude: 126.95100),
              blurb: "민주화를 위해 싸운 학생들을 기리는 동상."),
        .init(id: "jahayeon", name: "자하연", symbol: "drop.fill",
              coordinate: .init(latitude: 37.46109, longitude: 126.95380),
              blurb: "인문대와 학생회관 사이의 연못. 캠퍼스의 쉼터."),
        .init(id: "waterfall", name: "폭포", symbol: "water.waves",
              coordinate: .init(latitude: 37.45020, longitude: 126.95250),
              blurb: "관악산 자락을 따라 흐르는 캠퍼스의 폭포."),
        .init(id: "observatory", name: "전망대", symbol: "binoculars.fill",
              coordinate: .init(latitude: 37.44890, longitude: 126.95270),
              blurb: "관악 캠퍼스와 서울 시내가 한눈에 내려다보이는 곳."),
    ]

    /// `collected`에 없는 랜드마크 중 반경 안에서 가장 가까운 것.
    static func nearest(to position: CampusCoordinate, excluding collected: Set<String> = [],
                        within radius: Double = collectRadius) -> Landmark? {
        guard position.isValid else { return nil }
        return all
            .filter { !collected.contains($0.id) }
            .map { ($0, $0.coordinate.distance(to: position)) }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?.0
    }
}
