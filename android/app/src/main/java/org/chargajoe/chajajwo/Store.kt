package org.chargajoe.chajajwo

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.chargajoe.chajajwo.data.DiningData
import org.chargajoe.chajajwo.data.Place
import org.chargajoe.chajajwo.data.PlaceType

/** iOS Store의 지도·식당 부분. 화면 상태는 Compose 상태로 둔다. */
class Store(private val context: Context) {
    enum class Tab { HOME, QUESTS, DINING, LOST_FOUND, COMMUNITY, ME }
    enum class HomeFilter { ALL, QUESTS, FOOD, SHUTTLE, HUBS }

    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    var tab by mutableStateOf(Tab.HOME)
    var homeFilter by mutableStateOf(HomeFilter.ALL)
    var showDining by mutableStateOf(false) // 홈 탭 안에서 지도 대신 식당 화면을 보여준다
    var lostMapOnly by mutableStateOf(false)
    var sel by mutableStateOf(Place.all.firstOrNull()?.id ?: "")
    var open by mutableStateOf(false)
    var filter by mutableStateOf<PlaceType?>(null)
    var toastText by mutableStateOf<String?>(null)
        private set
    var dining by mutableStateOf(DiningData.startup())
        private set

    /** 방문 알림을 눌러 연 건물. 홈 화면이 받아서 건물 시트를 연다. */
    var pendingVisitBuildingID by mutableStateOf<String?>(null)
    var pendingVisitSerial by mutableIntStateOf(0)

    /** CI 스크린샷용 미리보기 인자(iOS -preview-* 대응). */
    var previewArgument: String? = null

    private var diningFetchedAt = 0L
    private var diningLoading = false
    private var toastJob: Job? = null

    fun select(id: String) {
        sel = id; open = true; showDining = false
    }

    fun closeSheet() { open = false }

    /** 최신 식단을 받아 온다. 실패하면 기존(캐시/번들) 식단을 그대로 쓴다. */
    fun refreshDining() {
        if (diningLoading || System.currentTimeMillis() - diningFetchedAt <= 600_000) return
        diningLoading = true
        scope.launch {
            try {
                val fresh = withContext(Dispatchers.IO) { DiningData.fetch() }
                if (fresh != null) {
                    val merged = dining.merged(fresh)
                    dining = merged
                    withContext(Dispatchers.IO) { merged.save() }
                    diningFetchedAt = System.currentTimeMillis()
                }
            } finally {
                diningLoading = false
            }
        }
    }

    fun toast(text: String) {
        toastText = text
        toastJob?.cancel()
        toastJob = scope.launch {
            delay(2200)
            if (toastText == text) toastText = null
        }
    }

    fun openVisit(buildingID: String) {
        pendingVisitBuildingID = buildingID
        pendingVisitSerial += 1
    }
}
