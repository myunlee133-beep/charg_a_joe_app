package org.chargajoe.chajajwo.data

import android.util.Log
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar
import java.util.Locale

enum class DiningMeal(val raw: String, val title: String) {
    BREAKFAST("BREAKFAST", "아침"), LUNCH("LUNCH", "점심"), DINNER("DINNER", "저녁")
}

/** 웹 수집기(GitHub Actions)가 만든 식단 스냅샷. 날짜가 다른 메뉴로 대체하지 않는다. */
@Serializable
data class DiningData(
    val schemaVersion: Int,
    val generatedAt: String,
    val dates: List<String>,
    val restaurants: List<Restaurant>,
    val menus: List<Menu>,
) {
    @Serializable
    data class Restaurant(
        val unit: String,
        val building: String? = null,
        val buildingName: String? = null,
        val weekdayHours: String = "",
        val saturdayHours: String = "",
        val holidayHours: String = "",
        val latitude: Double? = null,
        val longitude: Double? = null,
    )

    @Serializable
    data class Menu(
        val date: String? = null, // null이면 매일 같은 고정 메뉴(푸드코트 등)
        val unit: String,
        val building: String? = null,
        val meal: String,
        val name: String,
        val priceWon: Int? = null,
    )

    data class Stall(val stall: String, val menus: List<Menu>)
    data class Status(val title: String, val isOpen: Boolean)

    /** 건물별 메뉴. 7천여 개를 매번 훑지 않도록 처음 쓸 때 한 번 묶어 둔다. */
    private val menusByBuilding: Map<String, List<Menu>> by lazy {
        menus.filter { it.building != null }.groupBy { it.building!! }
    }

    companion object {
        const val UPDATE_NEEDED = "업데이트 필요"
        /** 아침·점심·저녁 구분 없이 매장별로 한 번에 보여주는 푸드코트 매장. */
        private val foodCourtPrefixes = listOf("4층 푸드코드 ", "220동식당 ")
        private val nameOverrides = mapOf("75-1동" to "75-1 식당가")
        const val ENDPOINT = "https://raw.githubusercontent.com/myunlee133-beep/chajajwo-meals-data/main/meals.json"
        const val PAST_DAYS = 30
        const val FUTURE_DAYS = 14

        fun isFoodCourt(unit: String): Boolean = unit == "버거운버거" || foodCourtPrefixes.any { unit.startsWith(it) }
        fun stallName(unit: String): String = foodCourtPrefixes.firstOrNull { unit.startsWith(it) }?.let { unit.drop(it.length) } ?: unit

        private val cacheFile: File get() = File(PlaceResources.context.cacheDir, "meals.json")

        fun decode(text: String): DiningData? = try {
            PlaceResources.json.decodeFromString<DiningData>(text).takeIf { it.schemaVersion == 1 && it.menus.isNotEmpty() }
        } catch (e: Exception) {
            Log.w("DiningData", "decode failed: $e"); null
        }

        /** 앱에 포함된 스냅샷. 오프라인 첫 실행용이자 식당 위치 목록의 기준. */
        val bundled: DiningData by lazy {
            PlaceResources.readText("meals.json")?.let { decode(it) } ?: DiningData(1, "", emptyList(), emptyList(), emptyList())
        }

        /** 마지막으로 받아 둔 스냅샷. 번들보다 오래됐으면 번들을 쓴다. */
        fun startup(): DiningData {
            val cached = try { if (cacheFile.exists()) decode(cacheFile.readText()) else null } catch (e: Exception) { null }
            return if (cached != null && cached.generatedAt > bundled.generatedAt) cached else bundled
        }

        fun fetch(): DiningData? = try {
            val conn = URL(ENDPOINT).openConnection() as HttpURLConnection
            conn.connectTimeout = 20_000
            conn.readTimeout = 20_000
            try {
                if (conn.responseCode == 200) decode(conn.inputStream.bufferedReader().use { it.readText() }) else null
            } finally { conn.disconnect() }
        } catch (e: Exception) {
            Log.w("DiningData", "fetch failed: $e"); null
        }

        fun dayKey(millis: Long): String {
            val c = seoulCalendar(millis)
            return String.format(Locale.ROOT, "%04d-%02d-%02d", c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
        }

        fun startOfDay(millis: Long): Long = seoulCalendar(millis).apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        fun addDays(millis: Long, days: Int): Long = seoulCalendar(millis).apply { add(Calendar.DAY_OF_MONTH, days) }.timeInMillis

        fun isToday(millis: Long): Boolean = dayKey(millis) == dayKey(System.currentTimeMillis())

        fun daysFromToday(millis: Long): Int {
            val a = startOfDay(System.currentTimeMillis())
            val b = startOfDay(millis)
            return Math.round((b - a) / 86_400_000.0).toInt()
        }

        /** 식단 화면에서 넘겨 볼 수 있는 범위: 오늘 기준 과거 한 달, 앞으로 2주. */
        fun canShow(millis: Long, offset: Int): Boolean {
            val days = daysFromToday(addDays(millis, offset))
            return days >= -PAST_DAYS && days <= FUTURE_DAYS
        }

        fun dateTitle(millis: Long): String {
            val c = seoulCalendar(millis)
            val weekday = CampusPlanning.dayName(c.get(Calendar.DAY_OF_WEEK))
            return "${c.get(Calendar.MONTH) + 1}월 ${c.get(Calendar.DAY_OF_MONTH)}일 ($weekday)"
        }

        /** "09 :00-20:00" 같은 표기 흔들림을 바로잡고, 괄호 설명과 문장은 버린 운영 구간들. */
        private fun ranges(schedule: String): List<String> {
            val text = schedule
                .replace(Regex("""\([^)]*\)"""), " ")
                .replace(Regex("""\s*:\s*"""), ":")
                .replace(Regex("""\s*-\s*"""), "-")
            return text.split(Regex("\\s+")).mapNotNull { token ->
                val times = token.split("-").map { part -> part.split(":").mapNotNull { it.toIntOrNull() } }
                if (times.size != 2 || times.any { it.size != 2 }) null
                else String.format(Locale.ROOT, "%02d:%02d-%02d:%02d", times[0][0], times[0][1], times[1][0], times[1][1])
            }
        }
    }

    /** 새로 받은 스냅샷을 합친다. 전체 기간이면 교체하고, 며칠치만 담겼으면 그 날짜만 덮어쓴다. */
    fun merged(fresh: DiningData): DiningData {
        if (fresh.dates.size >= dates.size) return fresh
        val freshDates = fresh.dates.toSet()
        val kept = menus.filter { it.date == null || it.date !in freshDates }
        return DiningData(1, fresh.generatedAt, dates, fresh.restaurants, kept + fresh.menus)
    }

    fun save() {
        try { cacheFile.writeText(PlaceResources.json.encodeToString(this)) } catch (e: Exception) { Log.w("DiningData", "save failed: $e") }
    }

    /** 좌표가 있는 식당을 건물 단위로 묶어 지도 핀으로 만든다. */
    val foodPlaces: List<Place>
        get() {
            val order = mutableListOf<String>()
            val groups = LinkedHashMap<String, MutableList<Restaurant>>()
            for (r in restaurants) {
                if (r.latitude == null || r.longitude == null) continue
                val building = r.building ?: continue
                if (!groups.containsKey(building)) order.add(building)
                groups.getOrPut(building) { mutableListOf() }.add(r)
            }
            return order.map { building ->
                val group = groups.getValue(building)
                val heads = group.map { it.unit.split(" ").firstOrNull() ?: it.unit }.toSet()
                val name = when {
                    group.size == 1 -> group[0].unit
                    heads.size == 1 -> heads.first()
                    else -> group[0].buildingName ?: building
                }
                Place("meal-$building", PlaceType.FOOD, nameOverrides[building] ?: name, group[0].latitude!!, group[0].longitude!!, building = building)
            }
        }

    private fun restaurants(place: Place, foodCourt: Boolean? = null): List<Restaurant> =
        restaurants.filter { it.building == place.building && (foodCourt == null || isFoodCourt(it.unit) == foodCourt) }

    fun hasUnits(place: Place, foodCourt: Boolean): Boolean = restaurants(place, foodCourt).isNotEmpty()

    private fun dayMenus(place: Place, millis: Long): List<Menu> {
        val key = dayKey(millis)
        return (menusByBuilding[place.building] ?: emptyList()).filter { it.date == key || it.date == null }
    }

    fun menus(place: Place, millis: Long, meal: DiningMeal): List<Menu> {
        val seen = HashSet<String>()
        return dayMenus(place, millis)
            .filter { it.meal == meal.raw && !isFoodCourt(it.unit) }
            .filter { seen.add("${it.unit}|${it.name}|${it.priceWon ?: 0}") }
    }

    /** 푸드코트는 끼니 구분 없이 매장별 메뉴 전부. 끼니마다 중복된 메뉴는 한 번만. */
    fun foodCourtMenus(place: Place, millis: Long): List<Stall> {
        val seen = HashSet<String>()
        val byUnit = LinkedHashMap<String, MutableList<Menu>>()
        for (menu in dayMenus(place, millis)) {
            if (!isFoodCourt(menu.unit)) continue
            if (!seen.add("${menu.unit}|${menu.name}|${menu.priceWon ?: 0}")) continue
            byUnit.getOrPut(menu.unit) { mutableListOf() }.add(menu)
        }
        return byUnit.map { (unit, list) -> Stall(stallName(unit), list) }
    }

    /** 건물 안 식당들의 운영 구간을 합친 시간표. 구간이 없으면 휴관 또는 "업데이트 필요". */
    fun hours(place: Place, millis: Long, foodCourt: Boolean? = null): String {
        val weekday = seoulCalendar(millis).get(Calendar.DAY_OF_WEEK)
        val schedules = restaurants(place, foodCourt).map {
            when (weekday) {
                Calendar.SUNDAY -> it.holidayHours
                Calendar.SATURDAY -> it.saturdayHours
                else -> it.weekdayHours
            }
        }
        val ranges = schedules.flatMap { ranges(it) }.toSet().sorted()
        if (ranges.isNotEmpty()) return ranges.joinToString(" ")
        return if (schedules.any { it.contains("휴관") }) "휴관" else UPDATE_NEEDED
    }

    fun foodCourtHours(place: Place, millis: Long): String {
        val schedule = hours(place, millis, foodCourt = true)
        if (schedule == "휴관") return "휴무"
        return if (schedule == UPDATE_NEEDED) schedule else schedule.split(" ").joinToString(" · ").replace("-", "–")
    }

    fun hours(place: Place, millis: Long, meal: DiningMeal): String {
        val schedule = hours(place, millis, foodCourt = false)
        if (schedule == "휴관") return "휴무"
        if (schedule == UPDATE_NEEDED) return schedule
        val ranges = schedule.split(" ").filter { range ->
            val hour = range.take(2).toIntOrNull() ?: return@filter false
            when (meal) {
                DiningMeal.BREAKFAST -> hour < 10
                DiningMeal.LUNCH -> hour in 10..15
                DiningMeal.DINNER -> hour >= 16
            }
        }
        return if (ranges.isEmpty()) "운영 없음" else ranges.joinToString(" · ").replace("-", "–")
    }

    fun status(place: Place, millis: Long): Status {
        val hours = hours(place, millis)
        if (hours.contains("휴관")) return Status("휴무", false)
        val intervals = hours.split(" ").mapNotNull { range ->
            val times = range.split("-").mapNotNull { time ->
                val parts = time.split(":").mapNotNull { it.toIntOrNull() }
                if (parts.size == 2) parts[0] * 60 + parts[1] else null
            }
            if (times.size == 2) times[0] to times[1] else null
        }
        if (intervals.isEmpty()) return Status(UPDATE_NEEDED, false)
        val minute = CampusPlanning.minuteOf(millis)
        val isOpen = intervals.any { minute >= it.first && minute < it.second }
        // 정규 시간표 기반 상태. 공휴일·임시 휴무는 별도 확인이 필요하다.
        return Status(if (isOpen) "운영 중" else "운영 종료", isOpen)
    }
}
