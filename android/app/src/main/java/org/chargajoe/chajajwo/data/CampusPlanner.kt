package org.chargajoe.chajajwo.data

import kotlinx.serialization.Serializable
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

val SeoulZone: TimeZone = TimeZone.getTimeZone("Asia/Seoul")

fun seoulCalendar(millis: Long = System.currentTimeMillis()): Calendar =
    Calendar.getInstance(SeoulZone, Locale.KOREA).apply { timeInMillis = millis }

@Serializable
data class CampusClass(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    /** Calendar weekday: Sunday = 1, Monday = 2. */
    val weekday: Int,
    val startMinute: Int,
    val endMinute: Int,
    val buildingNumber: String = "",
    val room: String = "",
    val colorIndex: Int = 0,
) {
    val isValid: Boolean
        get() = title.isNotBlank() && title.length <= 80 && weekday in 1..7 &&
            startMinute in 0 until 1440 && endMinute in 1..1440 && endMinute > startMinute
}

@Serializable
data class CampusVisitTask(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val buildingID: String,
    val location: String = "",
    val due: Long,
    val completed: Boolean = false,
    val reminderEnabled: Boolean = false,
) {
    val isValid: Boolean get() = title.isNotBlank() && title.length <= 120
}

@Serializable
data class CampusPlannerData(
    val classes: List<CampusClass> = emptyList(),
    val tasks: List<CampusVisitTask> = emptyList(),
    val favoriteBuildings: Set<String> = emptySet(),
)

data class CampusMinuteRange(val start: Int, val end: Int) {
    val duration: Int get() = end - start
    val label: String get() = "${CampusPlanning.time(start)} – ${CampusPlanning.time(end)}"
}

object CampusPlanning {
    fun time(minute: Int): String = String.format(Locale.ROOT, "%02d:%02d", minute / 60, minute % 60)

    fun minuteOf(millis: Long): Int {
        val c = seoulCalendar(millis)
        return c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
    }

    fun weekdayOf(millis: Long): Int = seoulCalendar(millis).get(Calendar.DAY_OF_WEEK)

    fun conflicts(candidate: CampusClass, classes: List<CampusClass>): Boolean = classes.any {
        it.id != candidate.id && it.weekday == candidate.weekday && it.isValid &&
            candidate.startMinute < it.endMinute && it.startMinute < candidate.endMinute
    }

    fun freeRanges(classes: List<CampusClass>, weekday: Int, window: CampusMinuteRange, minimumMinutes: Int = 30): List<CampusMinuteRange> {
        if (weekday !in 1..7 || window.start < 0 || window.end > 1440 || window.start >= window.end || minimumMinutes <= 0) return emptyList()
        val busy = classes.filter { it.isValid && it.weekday == weekday && it.endMinute > window.start && it.startMinute < window.end }
            .sortedBy { it.startMinute }
        var cursor = window.start
        val result = mutableListOf<CampusMinuteRange>()
        for (item in busy) {
            if (item.startMinute - cursor >= minimumMinutes) result.add(CampusMinuteRange(cursor, minOf(item.startMinute, window.end)))
            cursor = maxOf(cursor, item.endMinute)
        }
        if (window.end - cursor >= minimumMinutes) result.add(CampusMinuteRange(cursor, window.end))
        return result
    }

    fun parseHours(text: String): List<CampusMinuteRange> {
        val regex = Regex("""(\d{1,2}):(\d{2})\s*[-–~]\s*(\d{1,2}):(\d{2})""")
        return regex.findAll(text).mapNotNull { m ->
            val p = m.groupValues.drop(1).map { it.toInt() }
            if (p[1] >= 60 || p[3] >= 60) return@mapNotNull null
            val a = p[0] * 60 + p[1]
            val b = p[2] * 60 + p[3]
            if (a < 0 || a >= b || b > 1440) null else CampusMinuteRange(a, b)
        }.toList()
    }

    fun visitRanges(classes: List<CampusClass>, weekday: Int, openingHours: List<CampusMinuteRange>, after: Int = 0): List<CampusMinuteRange> {
        val merged = mutableListOf<CampusMinuteRange>()
        for (range in openingHours.filter { it.start >= 0 && it.end <= 1440 && it.start < it.end }.sortedBy { it.start }) {
            val previous = merged.lastOrNull()
            if (previous != null && range.start <= previous.end) merged[merged.size - 1] = previous.copy(end = maxOf(previous.end, range.end))
            else merged.add(range)
        }
        return merged.flatMap { hours ->
            freeRanges(classes, weekday, CampusMinuteRange(maxOf(hours.start, after), hours.end))
        }.sortedBy { it.start }
    }

    fun nextClass(classes: List<CampusClass>, nowMillis: Long = System.currentTimeMillis()): CampusClass? {
        val weekday = weekdayOf(nowMillis)
        val now = minuteOf(nowMillis)
        return classes.filter { it.isValid && it.weekday == weekday && it.startMinute > now }.minByOrNull { it.startMinute }
    }

    fun dayName(weekday: Int): String = listOf("일", "월", "화", "수", "목", "금", "토")[(weekday - 1).coerceIn(0, 6)]
}

data class CampusSpace(val id: String, val name: String, val building: CampusBuilding, val floor: String, val kind: String) {
    val locationLabel: String get() = building.buildingNumberLabel + " · " + floor

    companion object {
        val all: List<CampusSpace> by lazy {
            CampusBuildingCatalog.all.flatMap { building ->
                val venues = PlaceDirectory.venues(building)
                val cafes = venues.map { CampusSpace(it.id, it.name, building, it.floor, "카페") }
                val facilities = (building.details?.facilities ?: emptyList()).mapNotNull { facility ->
                    if (venues.any { v -> v.aliases.any { facility.name.contains(it) } }) return@mapNotNull null
                    // "도서관 ATM", "열람실 입구 AED" 같은 설비는 공강에 머물 공간이 아니다.
                    val kind = when {
                        facility.category == "카페" -> "카페"
                        facility.category in listOf("도서관", "열람실", "학습실", "스터디룸", "정보검색실") -> "도서·학습"
                        facility.category in listOf("라운지", "휴게실", "휴게공간") -> "라운지"
                        else -> return@mapNotNull null
                    }
                    CampusSpace(facility.id, facility.name, building, PlaceDirectory.floorName(facility.floor), kind)
                }
                cafes + facilities
            }
        }
    }
}

@Serializable
data class CampusBuildingPhoto(
    val buildingID: String,
    val photoURL: String,
    val sourceURL: String = "",
    val credit: String = "",
    val checkedAt: String = "",
    val assetName: String? = null,
    val sha256: String? = null,
) {
    val remoteURL: String?
        get() {
            val uri = try { android.net.Uri.parse(photoURL) } catch (e: Exception) { return null }
            return if (uri.scheme == "https" && uri.host == "map.snu.ac.kr" && (uri.path ?: "").startsWith("/api/upload/")) photoURL else null
        }

    companion object {
        val all: List<CampusBuildingPhoto> by lazy { PlaceResources.decode<List<CampusBuildingPhoto>>("building_photos") ?: emptyList() }
        fun photo(building: CampusBuilding): CampusBuildingPhoto? = all.firstOrNull { it.buildingID == building.id }
    }
}
