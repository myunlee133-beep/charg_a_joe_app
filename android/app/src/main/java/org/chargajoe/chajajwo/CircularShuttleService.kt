package org.chargajoe.chajajwo

import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.chargajoe.chajajwo.data.CircularFeed
import org.chargajoe.chajajwo.data.CircularRoute
import org.chargajoe.chajajwo.data.CircularShuttleTracker
import org.chargajoe.chajajwo.data.PlaceResources
import org.chargajoe.chajajwo.data.ShuttlePosition
import java.net.HttpURLConnection
import java.net.URL

/** 공개 엔드포인트는 GPS가 아닌 노선도 좌표를 준다. 41946 노선만 요청하고, 시뮬레이션 대체 표시는 없다. */
class CircularShuttleService {
    /** 애니메이션 중 1초에 20번 바뀐다. Compose 상태로 두지 않고 지도 핀에만 직접 알린다. */
    var positions: List<ShuttlePosition> = emptyList()
        private set(value) { field = value; onPositionsChange?.invoke() }
    var onPositionsChange: (() -> Unit)? = null

    var status by mutableStateOf("실시간 위치 확인 중")
        private set
    var queriedAt by mutableStateOf<Long?>(null)
        private set
    var heldCount by mutableIntStateOf(0)
        private set
    /** 상태 카드용. 5초마다(조회할 때) 갱신된다. */
    var statusPositions by mutableStateOf<List<ShuttlePosition>>(emptyList())
        private set

    private val tracker: CircularShuttleTracker? = CircularRoute.shared?.let { runCatching { CircularShuttleTracker(it) }.getOrNull() }

    private fun now(): Double = SystemClock.elapsedRealtime() / 1000.0

    suspend fun run() {
        val tracker = tracker ?: run { status = "노선 정보를 불러오지 못했어요"; return }
        try {
            coroutineScope {
                launch {
                    // 한 번의 렌더 루프가 느린 요청과 반복 좌표를 견딘다. 지도 핀만 갱신한다.
                    while (isActive) {
                        positions = moving(tracker, now())
                        delay(50)
                    }
                }
                while (isActive) {
                    val started = now()
                    try {
                        val feed = withContext(Dispatchers.IO) { fetch() }
                        if (!feed.validated(System.currentTimeMillis())) throw IllegalStateException("invalid feed")
                        tracker.update(feed.vehicles, now())
                        queriedAt = feed.queryEpochMillis
                        heldCount = tracker.heldCount
                        positions = moving(tracker, now())
                        statusPositions = positions
                        status = when {
                            feed.vehicles.isEmpty() -> "제공된 차량 위치가 없어요"
                            positions.isEmpty() -> "운행 중인 셔틀 확인 중"
                            else -> "교내순환 · 실시간 기반 추정 위치"
                        }
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        tracker.clear(); positions = emptyList(); statusPositions = emptyList(); heldCount = 0
                        status = "실시간 위치를 불러오지 못했어요"
                    }
                    val wait = maxOf(0.0, POLL_INTERVAL - (now() - started))
                    delay((wait * 1000).toLong())
                }
            }
        } finally {
            tracker.clear(); positions = emptyList(); statusPositions = emptyList(); heldCount = 0
        }
    }

    private fun fetch(): CircularFeed {
        val conn = URL("https://chajajwo-web-mu.vercel.app/api/shuttle?route=41946").openConnection() as HttpURLConnection
        conn.useCaches = false
        conn.connectTimeout = 7000
        conn.readTimeout = 7000
        try {
            if (conn.responseCode != 200) throw IllegalStateException("HTTP ${conn.responseCode}")
            val text = conn.inputStream.bufferedReader().use { it.readText() }
            return PlaceResources.json.decodeFromString(CircularFeed.serializer(), text)
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        private const val POLL_INTERVAL = 5.0

        /** 앱을 켠 뒤 한 번이라도 움직인 차량만 보여준다. */
        private fun moving(tracker: CircularShuttleTracker, now: Double): List<ShuttlePosition> =
            tracker.positions(now).filter { it.changes > 0 }
    }
}
