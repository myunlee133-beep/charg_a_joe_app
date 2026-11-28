package org.chargajoe.chajajwo.data

import android.util.Log
import kotlinx.serialization.Serializable
import java.net.URLEncoder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot

@Serializable
data class CampusCoordinate(val latitude: Double, val longitude: Double) {
    val isValid: Boolean
        get() = latitude.isFinite() && longitude.isFinite() && abs(latitude) <= 90 && abs(longitude) <= 180

    fun distanceTo(other: CampusCoordinate): Double =
        hypot((other.latitude - latitude) * 111195, (other.longitude - longitude) * 111195 * cos(latitude * PI / 180))

    fun bearingTo(other: CampusCoordinate): Double {
        val angle = atan2((other.longitude - longitude) * cos(latitude * PI / 180), other.latitude - latitude)
        return (angle + 2 * PI) % (2 * PI)
    }
}

/** 2026년 10월 서울대 캠퍼스맵 스냅샷 + OSM 건물 2곳. 오프라인 카탈로그. */
@Serializable
data class CampusBuilding(
    val id: String,
    val number: String? = null,
    val name: String,
    val latitude: Double,
    val longitude: Double,
    val source: String = "",
    val details: CampusBuildingDetails? = null,
) {
    val buildingNumberLabel: String
        get() = if (number.isNullOrEmpty()) "캠퍼스 장소" else number + "동"

    val displayTitle: String get() = if (number == null) name else "$buildingNumberLabel · $name"

    val coordinate: CampusCoordinate get() = CampusCoordinate(latitude, longitude)

    val mapURL: String
        get() {
            val encoded = URLEncoder.encode(displayTitle, "UTF-8").replace("+", "%20")
            return "https://map.kakao.com/link/map/$encoded,$latitude,$longitude"
        }

    val directionsURL: String? get() = DirectionsURL.destination(name, latitude, longitude)

    val directionsEndpoint: DirectionsEndpoint get() = DirectionsEndpoint(displayTitle, latitude, longitude)
}

@Serializable
data class CampusBuildingDetails(
    val category: String = "",
    val summary: String = "",
    val englishName: String? = null,
    val address: String? = null,
    val phone: String? = null,
    val website: String? = null,
    val usage: String = "",
    val facilities: List<CampusBuildingFacility> = emptyList(),
    val accessibility: List<String> = emptyList(),
    val notices: List<CampusBuildingNotice> = emptyList(),
    val sources: List<CampusBuildingSource> = emptyList(),
    val checkedAt: String = "",
) {
    val phoneURL: String?
        get() {
            val phone = phone ?: return null
            val match = Regex("""0\d{1,2}[- ]\d{3,4}[- ]\d{4}""").find(phone) ?: return null
            return "tel:" + match.value.filter { it.isDigit() }
        }

    val websiteURL: String?
        get() = website?.takeIf { it.startsWith("https://") }
}

@Serializable
data class CampusBuildingFacility(val id: String, val name: String, val floor: String? = null, val category: String = "")

@Serializable
data class CampusBuildingNotice(val title: String, val body: String, val sourceURL: String, val checkedAt: String = "")

@Serializable
data class CampusBuildingSource(val title: String, val url: String, val checkedAt: String = "")

object CampusBuildingCatalog {
    val all: List<CampusBuilding> by lazy { load() }

    private fun load(): List<CampusBuilding> {
        val items = PlaceResources.decode<List<CampusBuilding>>("campus_buildings")
        if (items == null) {
            Log.w("CampusBuildingCatalog", "campus_buildings.json is missing or invalid")
            return emptyList()
        }
        return items.filter {
            it.latitude.isFinite() && it.longitude.isFinite() &&
                it.latitude in 37.4..37.51 && it.longitude in 126.9..127.0
        }
    }

    /** 공백으로 나눈 모든 단어를 AND로 비교한다. 결과 개수 제한 없음. */
    fun search(query: String, among: List<CampusBuilding> = all, includeFacilityNames: Boolean = true): List<CampusBuilding> {
        val terms = query.split(Regex("\\s+")).map { it.compactKey() }.filter { it.isNotEmpty() }
        if (terms.isEmpty()) return emptyList()
        val queryKey = query.compactKey()
        return among.filter { building ->
            val number = building.number ?: ""
            val facilityNames = if (includeFacilityNames) building.details?.facilities?.map { it.name } ?: emptyList() else emptyList()
            val fields = (listOf(number, number + "동", building.name) + facilityNames).map { it.compactKey() }
            val english = building.details?.englishName ?: ""
            val englishWords = english.split(Regex("[^\\p{L}]+")).map { it.compactKey() }
            terms.all { term ->
                if (fields.any { it.contains(term) }) return@all true
                // CU 같은 짧은 영문은 moleCUlar, faCUlty에 걸리지 않게 단어 단위로만 비교한다.
                val shortLatin = term.length <= 2 && term.all { it in 'a'..'z' }
                if (shortLatin) englishWords.contains(term) else english.compactKey().contains(term)
            }
        }.sortedWith { lhs, rhs ->
            val lhsExact = lhs.number?.let { it.compactKey() == queryKey || (it + "동").compactKey() == queryKey } ?: false
            val rhsExact = rhs.number?.let { it.compactKey() == queryKey || (it + "동").compactKey() == queryKey } ?: false
            when {
                lhsExact != rhsExact -> if (lhsExact) -1 else 1
                (lhs.number == null) != (rhs.number == null) -> if (lhs.number != null) -1 else 1
                else -> naturalOrder.compare(lhs.displayTitle, rhs.displayTitle)
            }
        }
    }

    fun nearest(latitude: Double, longitude: Double, withinMetres: Double, among: List<CampusBuilding> = all): CampusBuilding? {
        if (!latitude.isFinite() || !longitude.isFinite() || !withinMetres.isFinite() || withinMetres < 0) return null
        val radians = PI / 180
        return among.mapNotNull { building ->
            val dy = (building.latitude - latitude) * radians
            val dx = (building.longitude - longitude) * radians * cos((building.latitude + latitude) / 2 * radians)
            val distance = 6_371_000 * hypot(dx, dy)
            if (distance.isFinite() && distance <= withinMetres) building to distance else null
        }.minByOrNull { it.second }?.first
    }

    val sortedByTitle: List<CampusBuilding> by lazy { all.sortedWith { a, b -> naturalOrder.compare(a.displayTitle, b.displayTitle) } }
}

/** 지도 기본 라벨을 누르지 않았을 때의 건물 선택. 화면 거리와 실제 미터 거리 둘 다 본다. */
object CampusBuildingHitTest {
    data class Target(val id: String, val coordinate: CampusCoordinate, val x: Float, val y: Float)

    fun select(x: Float, y: Float, coordinate: CampusCoordinate, zoom: Int, targets: List<Target>, density: Float): String? {
        if (zoom < 15 || !coordinate.isValid || !x.isFinite() || !y.isFinite()) return null
        return targets.mapNotNull { target ->
            if (!target.coordinate.isValid || !target.x.isFinite() || !target.y.isFinite() ||
                coordinate.distanceTo(target.coordinate) > 45) return@mapNotNull null
            val distance = hypot((target.x - x) / density, (target.y - y) / density)
            if (distance > 32) null else target.id to distance
        }.minWithOrNull(compareBy<Pair<String, Float>> { it.second }.thenBy { it.first })?.first
    }
}
