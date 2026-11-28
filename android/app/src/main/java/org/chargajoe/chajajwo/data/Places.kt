package org.chargajoe.chajajwo.data

enum class PlaceType(val chipTitle: String) {
    HUB("보관 거점"), FOOD("식당"), STOP("셔틀")
}

data class Place(
    val id: String,
    val type: PlaceType,
    val name: String,
    val lat: Double,
    val lng: Double,
    val hours: String = "",
    val building: String = "",
    val storage: String = "",
) {
    val directionsURL: String? get() = DirectionsURL.destination(name, lat, lng)

    companion object {
        val all: List<Place> by lazy {
            DiningData.bundled.foodPlaces + listOf(
                Place("hub1", PlaceType.HUB, "학생회관 보관 거점", 37.4617, 126.9520, storage = "학생회관 1층 안내데스크"),
                Place("hub2", PlaceType.HUB, "정문 셔틀 정류장 거점", 37.4659, 126.9489, storage = "정문 셔틀 정류장 옆 보관함"),
                Place("hub3", PlaceType.HUB, "신공학관 셔틀 종점 거점", 37.4495, 126.9512, storage = "신공학관 1층 경비실"),
            ) + (CircularRoute.shared?.stops?.mapIndexed { index, stop ->
                Place("circular-stop-$index", PlaceType.STOP, stop.name + " · 교내순환", stop.coordinate.latitude, stop.coordinate.longitude)
            } ?: emptyList())
        }
        val byID: Map<String, Place> by lazy { all.associateBy { it.id } }
    }
}

enum class TreasureGrade(val title: String) { COMMON("일반"), RARE("희귀"), LEGENDARY("전설") }

/** 캠퍼스에 숨은 보물. 반경 안에 들어가면 지도에 여우가 나타난다(AR 수집은 다음 단계). */
data class Landmark(
    val id: String,
    val name: String,
    val place: String,
    val grade: TreasureGrade,
    val art: String,
    val coordinate: CampusCoordinate,
    val clue: String,
    val blurb: String,
) {
    companion object {
        const val COLLECT_RADIUS = 50.0
        val all = listOf(
            Landmark("fox", "탐험 여우", "정문", TreasureGrade.COMMON, "Treasure-fox", CampusCoordinate(37.46630, 126.94835),
                "한 번쯤 사진을 찍지 않았을까?", "서울대의 첫인상, 정문 앞을 지키던 탐험 여우. 이제 함께 캠퍼스를 누벼요."),
            Landmark("key", "숨겨진 열쇠", "자하연", TreasureGrade.COMMON, "Treasure-key", CampusCoordinate(37.46109, 126.95380),
                "꽥꽥꽥", "자하연 오리가 물고 있던 열쇠. 무엇을 여는 열쇠일까요?"),
            Landmark("doraji", "도라지", "중앙도서관", TreasureGrade.RARE, "Treasure-doraji", CampusCoordinate(37.45940, 126.95199),
                "도라지", "중앙도서관 어딘가에서 자라난 도라지. 책 냄새를 좋아해요."),
            Landmark("ghost", "공학 유령", "붉은 광장", TreasureGrade.COMMON, "Treasure-ghost", CampusCoordinate(37.45587, 126.95123),
                "하나의 유령이 공대를 배회하고 있다.", "아랫공대 붉은 광장을 떠도는 유령. 생각보다 친절해요."),
            Landmark("reed", "갈댓닢", "하늘 정원", TreasureGrade.RARE, "Treasure-reed", CampusCoordinate(37.45903, 126.95247),
                "슬슬 추워지는 거 같아", "하늘 정원 바람에 흔들리던 갈댓잎 한 장."),
            Landmark("sombrero", "하얀 솜브레로", "셔틀 승차장", TreasureGrade.RARE, "Treasure-sombrero", CampusCoordinate(37.46590, 126.94890),
                "¡vamos todos! 출발할 시간이야", "셔틀 승차장에 누가 두고 간 하얀 솜브레로."),
            Landmark("teapot", "파란 주전자", "블루포트", TreasureGrade.LEGENDARY, "Treasure-teapot", CampusCoordinate(37.465012, 126.957503),
                "커피를 디자인하다", "블루포트의 파란 주전자. 커피 향이 아직 남아 있어요."),
            Landmark("bear", "공대곰돌이", "39동", TreasureGrade.LEGENDARY, "Treasure-bear", CampusCoordinate(37.45465, 126.95157),
                "문 좀 닫아줘…", "39동 문 앞을 지키는 공대곰돌이. 문은 꼭 닫아 주세요."),
            Landmark("trophy", "마이너 트로피", "기숙사 라커", TreasureGrade.LEGENDARY, "Treasure-trophy", CampusCoordinate(37.46149, 126.95810),
                "어쩌다 관악사는 강팀이 되었는가", "기숙사 라커에 잠들어 있던 관악사의 트로피."),
        )

        fun nearby(position: CampusCoordinate, excluding: Set<String> = emptySet(), within: Double = COLLECT_RADIUS): List<Landmark> {
            if (!position.isValid) return emptyList()
            return all.filter { it.id !in excluding }
                .map { it to it.coordinate.distanceTo(position) }
                .filter { it.second <= within }
                .sortedBy { it.second }
                .map { it.first }
        }
    }
}
