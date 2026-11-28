package org.chargajoe.chajajwo.data

import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.OffsetDateTime
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

@Serializable
data class CircularRoute(
    val routeId: String,
    val stops: List<Stop>,
    val segments: List<List<List<Double>>>,
) {
    @Serializable
    data class Stop(val name: String, val diagram: List<Double>, val geo: List<Double>) {
        val coordinate: CampusCoordinate get() = CampusCoordinate(geo[0], geo[1])
    }

    val isValid: Boolean
        get() = routeId == "41946" && stops.size >= 2 && segments.size == stops.size &&
            stops.all { it.diagram.size == 2 && it.diagram.all { d -> d.isFinite() } && it.geo.size == 2 && it.coordinate.isValid } &&
            segments.all { seg -> seg.size >= 2 && seg.all { it.size == 2 && CampusCoordinate(it[0], it[1]).isValid } }

    companion object {
        val shared: CircularRoute? by lazy { PlaceResources.decode<CircularRoute>("circular_route")?.takeIf { it.isValid } }
    }
}

@Serializable
data class CircularFeed(val routeId: String, val checkedAt: String, val vehicles: List<Vehicle>) {
    @Serializable
    data class Vehicle(val id: String, val x: Double, val y: Double) {
        val isValid: Boolean
            get() = Regex("^[A-Za-z0-9_.:-]{1,64}$").matches(id) &&
                x.isFinite() && y.isFinite() && x in 90.0..220.0 && y in 20.0..420.0
    }

    val queryEpochMillis: Long?
        get() = try {
            OffsetDateTime.parse(checkedAt).toInstant().toEpochMilli()
        } catch (e: Exception) {
            try { Instant.parse(checkedAt).toEpochMilli() } catch (e2: Exception) { null }
        }

    fun validated(nowMillis: Long): Boolean {
        val date = queryEpochMillis ?: return false
        if (routeId != "41946") return false
        val age = (nowMillis - date) / 1000.0
        return age in -5.0..20.0 && vehicles.all { it.isValid }
    }
}

data class ShuttlePosition(
    val id: String,
    val coordinate: CampusCoordinate,
    val bearingRadians: Double,
    val nextStop: String,
    val movementAge: Double?,
    val changes: Int,
)

/** iOS CircularShuttleTracker 포팅. 노선도 픽셀 매칭과 도로 미터를 분리한다. */
class CircularShuttleTracker(val route: CircularRoute) {
    companion object {
        const val INTERPOLATION = 5.0
        const val MAXIMUM_INTERPOLATION = 30.0
        const val STALE_AFTER = 20.0
        /** 이 시간 동안 도로 위 위치가 안 바뀐 차량은 주차·대기로 보고 숨긴다. */
        const val PARKED_AFTER = 180.0
    }

    private data class Bus(
        val id: String, var x: Double, var y: Double, var diagram: Double, var road: Double, var fromRoad: Double,
        var animationAt: Double, var movedAt: Double, var seenAt: Double,
        var animationDuration: Double = INTERPOLATION, var changes: Int = 0, var visible: Boolean = true,
    ) {
        fun display(now: Double): Double {
            val t = min(1.0, max(0.0, (now - animationAt) / animationDuration))
            return fromRoad + (road - fromRoad) * t
        }
    }

    private var buses = HashMap<String, Bus>()
    private val diagramDistances = mutableListOf(0.0)
    private val roadStarts = mutableListOf<Double>()
    private val roadLengths = mutableListOf<Double>()
    private val roadPoints = mutableListOf<CampusCoordinate>()
    private val roadDistances = mutableListOf(0.0)
    var heldCount = 0
        private set
    val totalRoadDistance: Double get() = roadDistances.last()
    val totalDiagramDistance: Double get() = diagramDistances.last()

    init {
        require(route.isValid)
        var start = 0.0
        for (i in route.stops.indices) {
            val a = route.stops[i].diagram
            val b = route.stops[(i + 1) % route.stops.size].diagram
            diagramDistances.add(diagramDistances.last() + hypot(b[0] - a[0], b[1] - a[1]))
            val points = route.segments[i].map { CampusCoordinate(it[0], it[1]) }
            val length = points.zipWithNext().sumOf { (p, q) -> p.distanceTo(q) }
            roadStarts.add(start); roadLengths.add(length); start += length
            if (i + 1 < route.segments.size) {
                val p = route.segments[i + 1][0]
                start += points.last().distanceTo(CampusCoordinate(p[0], p[1]))
            }
            roadPoints += points
        }
        for (i in 1 until roadPoints.size) roadDistances.add(roadDistances.last() + roadPoints[i - 1].distanceTo(roadPoints[i]))
        require(totalRoadDistance > 0 && totalDiagramDistance > 0)
    }

    fun clear() { buses.clear(); heldCount = 0 }

    private fun modulo(value: Double, total: Double): Double {
        val r = value % total
        return if (r < 0) r + total else r
    }

    private fun segment(distance: Double): Pair<Int, Double> {
        val d = modulo(distance, totalDiagramDistance)
        val found = (1 until diagramDistances.size).firstOrNull { d <= diagramDistances[it] } ?: 1
        val index = max(0, found - 1)
        return index to (d - diagramDistances[index]) / max(0.001, diagramDistances[index + 1] - diagramDistances[index])
    }

    fun roadDistance(atDiagram: Double): Double {
        val (i, t) = segment(atDiagram)
        return floor(atDiagram / totalDiagramDistance) * totalRoadDistance + roadStarts[i] + roadLengths[i] * t
    }

    fun coordinate(at: Double): CampusCoordinate {
        val d = modulo(at, totalRoadDistance)
        val i = max(1, (1 until roadDistances.size).firstOrNull { d <= roadDistances[it] } ?: 1)
        val a = roadPoints[i - 1]
        val b = roadPoints[i]
        val t = (d - roadDistances[i - 1]) / max(Double.MIN_VALUE, roadDistances[i] - roadDistances[i - 1])
        return CampusCoordinate(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t)
    }

    private fun project(row: CircularFeed.Vehicle, previous: Double?): Pair<Double, Double>? {
        var best: Triple<Double, Double, Double>? = null
        for (i in route.stops.indices) {
            val a = route.stops[i].diagram
            val b = route.stops[(i + 1) % route.stops.size].diagram
            val dx = b[0] - a[0]
            val dy = b[1] - a[1]
            val length = dx * dx + dy * dy
            if (length <= 0.01) continue
            val t = max(0.0, min(1.0, ((row.x - a[0]) * dx + (row.y - a[1]) * dy) / length))
            val error = hypot(row.x - a[0] - t * dx, row.y - a[1] - t * dy)
            var distance = diagramDistances[i] + t * sqrt(length)
            var score = error
            if (previous != null) {
                distance += ((previous - distance) / totalDiagramDistance).let { swiftRound(it) } * totalDiagramDistance
                if (distance < previous - totalDiagramDistance * 0.5) distance += totalDiagramDistance
                if (distance > previous + totalDiagramDistance * 0.5) distance -= totalDiagramDistance
                val delta = distance - previous
                score += if (delta < -5) 25 + abs(delta) * 0.3 else max(0.0, delta - 75) * 0.15
            }
            if (best == null || score < best.third) best = Triple(distance, error, score)
        }
        return best?.let { it.first to it.second }
    }

    /** Swift `.rounded()` = 0.5에서 0에서 먼 쪽으로 반올림. */
    private fun swiftRound(v: Double): Double = if (v >= 0) floor(v + 0.5) else -floor(-v + 0.5)

    fun update(rows: List<CircularFeed.Vehicle>, now: Double) {
        val next = HashMap<String, Bus>()
        heldCount = 0
        for (row in rows) {
            if (!row.isValid || next.containsKey(row.id)) continue
            var old = buses[row.id]
            if (old != null && now - old.seenAt >= STALE_AFTER) old = null
            val match = project(row, old?.diagram)
            if (match == null || match.second > 24) {
                if (old != null) { old.visible = false; next[row.id] = old }
                heldCount += 1; continue
            }
            if (old == null) {
                val road = roadDistance(match.first)
                next[row.id] = Bus(row.id, row.x, row.y, match.first, road, road, now, now, now)
                continue
            }
            val bus = old
            bus.visible = true
            if (hypot(row.x - bus.x, row.y - bus.y) >= 0.7) {
                val delta = match.first - bus.diagram
                val road = roadDistance(max(bus.diagram, match.first))
                val seconds = max(1.0, now - bus.movedAt)
                if (delta < -5 || delta > max(28.0, seconds * 7 + 16) || road - bus.road > seconds * 15 + 35) {
                    bus.visible = false; heldCount += 1; next[row.id] = bus; continue
                }
                if (road - bus.road > 0.01) {
                    // 정류장 단위로 듬성듬성 오는 갱신도 도로를 따라 움직인다. 현재 프레임에서 다시 출발한다.
                    bus.fromRoad = bus.display(now)
                    bus.animationDuration = min(MAXIMUM_INTERPOLATION, max(INTERPOLATION, seconds))
                    bus.diagram = max(bus.diagram, match.first); bus.road = road
                    bus.animationAt = now; bus.movedAt = now; bus.changes += 1
                    bus.x = row.x; bus.y = row.y
                }
            }
            bus.seenAt = now
            next[row.id] = bus
        }
        buses = next
    }

    fun positions(now: Double): List<ShuttlePosition> =
        buses.values.filter { it.visible && now - it.seenAt < STALE_AFTER && now - it.movedAt < PARKED_AFTER }
            .sortedBy { it.id }
            .map { bus ->
                val distance = bus.display(now)
                val point = coordinate(distance)
                val (index, t) = segment(diagramDistance(atRoad = distance))
                ShuttlePosition(
                    id = bus.id,
                    coordinate = point,
                    bearingRadians = point.bearingTo(coordinate(distance + 5)),
                    nextStop = route.stops[(index + (if (t > 0.999) 2 else 1)) % route.stops.size].name,
                    movementAge = if (bus.changes > 0) max(0.0, now - bus.movedAt) else null,
                    changes = bus.changes,
                )
            }

    private fun diagramDistance(atRoad: Double): Double {
        val d = modulo(atRoad, totalRoadDistance)
        val index = roadStarts.indices.lastOrNull { roadStarts[it] <= d } ?: 0
        val t = min(1.0, max(0.0, (d - roadStarts[index]) / max(0.001, roadLengths[index])))
        return diagramDistances[index] + (diagramDistances[index + 1] - diagramDistances[index]) * t
    }
}
