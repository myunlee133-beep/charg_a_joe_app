package org.chargajoe.chajajwo

import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.kakao.vectormap.KakaoMapSdk
import org.chargajoe.chajajwo.data.PlaceResources

class ChajajwoApp : Application() {
    lateinit var store: Store
        private set
    lateinit var planner: CampusPlannerStore
        private set
    lateinit var landmarks: LandmarkCollection
        private set
    val shuttle = CircularShuttleService()

    override fun onCreate() {
        super.onCreate()
        PlaceResources.init(this)
        val key = runCatching {
            packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
                .metaData?.getString("org.chargajoe.chajajwo.KAKAO_APP_KEY")
        }.getOrNull() ?: ""
        try { KakaoMapSdk.init(this, key) } catch (e: Throwable) { Log.e("ChajajwoApp", "카카오맵 초기화 실패", e) }
        store = Store(this)
        planner = CampusPlannerStore(this)
        landmarks = LandmarkCollection(this)
    }
}

/** 발견한 보물 id. 기기에만 저장한다(AR 수집 화면은 다음 단계에서 연결). */
class LandmarkCollection(context: Context) {
    private val prefs = context.getSharedPreferences("cj_landmarks", Context.MODE_PRIVATE)
    var ids by mutableStateOf(prefs.getStringSet("collectedLandmarks", emptySet())!!.toSet())
        private set

    fun collect(id: String) {
        if (id in ids) return
        ids = ids + id
        prefs.edit().putStringSet("collectedLandmarks", ids).apply()
    }
}
