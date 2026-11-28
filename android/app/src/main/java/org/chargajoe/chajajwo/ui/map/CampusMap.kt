package org.chargajoe.chajajwo.ui.map

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.kakao.vectormap.KakaoMap
import com.kakao.vectormap.KakaoMapReadyCallback
import com.kakao.vectormap.LatLng
import com.kakao.vectormap.MapLifeCycleCallback
import com.kakao.vectormap.MapView
import com.kakao.vectormap.camera.CameraAnimation
import com.kakao.vectormap.camera.CameraUpdateFactory
import com.kakao.vectormap.label.CompetitionType
import com.kakao.vectormap.label.Label
import com.kakao.vectormap.label.LabelLayer
import com.kakao.vectormap.label.LabelLayerOptions
import com.kakao.vectormap.label.LabelOptions
import com.kakao.vectormap.label.LabelStyle
import com.kakao.vectormap.label.LabelStyles
import com.kakao.vectormap.label.LabelTextBuilder
import com.kakao.vectormap.label.LabelTextStyle
import com.kakao.vectormap.label.OrderingType
import com.kakao.vectormap.label.TransformMethod
import org.chargajoe.chajajwo.CircularShuttleService
import org.chargajoe.chajajwo.data.CampusAmenityKind
import org.chargajoe.chajajwo.data.CampusAmenityMapGroup
import org.chargajoe.chajajwo.data.CampusBuilding
import org.chargajoe.chajajwo.data.CampusBuildingCatalog
import org.chargajoe.chajajwo.data.CampusBuildingHitTest
import org.chargajoe.chajajwo.data.CampusCoordinate
import org.chargajoe.chajajwo.data.Landmark
import org.chargajoe.chajajwo.data.Place
import org.chargajoe.chajajwo.data.PlaceType
import org.chargajoe.chajajwo.ui.Sym
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.random.Random

/** 지도에 그릴 내용. iOS KakaoMapView의 프로퍼티와 같다. */
data class CampusMapState(
    val places: List<Place>,
    val selected: String,
    val bottomInsetPx: Int,
    val topObstructionPx: Int,
    val focusedBuilding: CampusBuilding?,
    val focusSerial: Int,
    val userCoordinate: CampusCoordinate?,
    val userHeadingDegrees: Double?,
    val userFocusSerial: Int,
    val treasures: List<Landmark>,
    val zoomRequest: Int,
    val amenityGroups: List<CampusAmenityMapGroup>,
    val active: Boolean,
    val initialLevel: Int = 15,
    val initialCoordinate: CampusCoordinate = CampusCoordinate(37.4600, 126.9520),
)

class CampusMapCallbacks(
    val onTreasureSelect: (String) -> Unit,
    val onSelectAmenityBuilding: (CampusBuilding) -> Unit,
    val onDeselect: () -> Unit,
    val onSelectBuilding: (CampusBuilding) -> Unit,
    val onSelect: (String) -> Unit,
    val onTouch: () -> Unit,
)

@Composable
fun CampusMapView(state: CampusMapState, callbacks: CampusMapCallbacks, shuttle: CircularShuttleService, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val buildingPainter = rememberVectorPainter(Icons.Filled.Apartment)
    val amenityPainters = CampusAmenityKind.entries.associateWith { rememberVectorPainter(Sym.amenity(it)) }
    val controller = remember { CampusMapController(context, shuttle) }
    controller.bitmaps = remember { PinBitmaps(context, PinPainters(buildingPainter, amenityPainters)) }
    controller.callbacks = callbacks

    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> controller.resume()
                Lifecycle.Event.ON_PAUSE -> controller.pause()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            controller.tearDown()
        }
    }

    AndroidView(
        modifier = modifier,
        factory = { controller.createView(state) },
        update = { controller.update(state) },
    )
}

/** iOS KakaoMapView.Coordinator 포팅. 카카오맵 라벨(POI)을 상태에 맞게 갱신한다. */
class CampusMapController(private val context: Context, private val shuttle: CircularShuttleService) {
    lateinit var bitmaps: PinBitmaps
    lateinit var callbacks: CampusMapCallbacks
    private var state: CampusMapState? = null
    private var mapView: MapView? = null
    private var map: KakaoMap? = null
    private val handler = Handler(Looper.getMainLooper())
    private val density = context.resources.displayMetrics.density
    private var resumed = false

    private val styles = HashMap<String, LabelStyles>()
    private val placeLabels = HashMap<String, Label>()
    private val placeStyle = HashMap<String, String>()
    private val buildingLabels = HashMap<String, Label>()
    private val amenityLabels = HashMap<String, Label>()
    private val amenityStyle = HashMap<String, String>()
    private val shuttleLabels = HashMap<String, Label>()
    private val treasureLabels = HashMap<String, Label>()
    private var userDot: Label? = null
    private var userDirection: Label? = null
    private var lastBuildingID: String? = null
    private var lastFocusSerial = -1
    private var lastSelected: String? = null
    private var lastZoomRequest = 0
    private var lastUserFocusSerial = 0
    private var lastInsets = Pair(0, 0)
    private var pinsVisible = false
    private var lastLabelTapAt = 0L
    private var lastBuildingTapAt = 0L
    private var lastBuildingTapID: String? = null
    private var foxRunnable: Runnable? = null

    companion object {
        /** 이 레벨보다 멀리서 볼 때는 핀을 모두 숨긴다(기본 화면은 레벨 15). */
        const val MIN_PIN_LEVEL = 14
        const val MIN_SHUTTLE_LEVEL = 15
        const val PLACES = "places"
        const val USER = "user-location"
        const val SHUTTLE = "circular-shuttle"
        const val TREASURE = "treasure-fox"
    }

    fun createView(initial: CampusMapState): MapView {
        state = initial
        val view = MapView(context)
        view.contentDescription = "캠퍼스 지도"
        mapView = view
        view.start(object : MapLifeCycleCallback() {
            override fun onMapDestroy() { map = null }
            override fun onMapError(error: Exception) { Log.e("CampusMap", "카카오맵 오류(키 해시 등록 확인): ${error.message}", error) }
        }, object : KakaoMapReadyCallback() {
            override fun onMapReady(kakaoMap: KakaoMap) { mapReady(kakaoMap) }
            override fun getPosition(): LatLng = LatLng.from(initial.initialCoordinate.latitude, initial.initialCoordinate.longitude)
            override fun getZoomLevel(): Int = initial.initialLevel
        })
        resumed = true
        return view
    }

    fun resume() { if (state?.active != false) { mapView?.resume(); resumed = true } }
    fun pause() { mapView?.pause(); resumed = false }

    fun tearDown() {
        foxRunnable?.let { handler.removeCallbacks(it) }
        foxRunnable = null
        shuttle.onPositionsChange = null
        runCatching { mapView?.finish() }
        mapView = null
        map = null
    }

    private fun mapReady(kakaoMap: KakaoMap) {
        map = kakaoMap
        kakaoMap.setPoiClickable(true) // 지도 기본 건물 이름도 누를 수 있다.
        val manager = kakaoMap.labelManager ?: return
        fun layer(id: String, z: Int, clickable: Boolean) {
            manager.addLayer(LabelLayerOptions.from(id).setZOrder(z).setCompetitionType(CompetitionType.None)
                .setOrderingType(OrderingType.Rank).setClickable(clickable))
        }
        // 지도 기본 글자보다 위에 그려야 이름표가 안 가려진다.
        layer(PLACES, 20000, true)
        layer(SHUTTLE, 24000, false)
        layer(USER, 25000, false)
        layer(TREASURE, 26000, true)
        kakaoMap.setOnLabelClickListener { _, _, label ->
            labelTapped(label)
            true
        }
        kakaoMap.setOnPoiClickListener { _, position, layerId, _ ->
            poiTapped(position, layerId)
        }
        kakaoMap.setOnMapClickListener { m, position, point, _ ->
            // 같은 터치의 라벨 탭 이벤트가 먼저 처리되도록 한 박자 미룬다.
            handler.post { mapTapped(m, position, point.x, point.y) }
        }
        kakaoMap.setOnCameraMoveEndListener { _, _, _ -> refresh() }
        shuttle.onPositionsChange = { handler.post { refreshShuttles() } }
        refresh()
    }

    fun update(next: CampusMapState) {
        val wasActive = state?.active
        state = next
        if (wasActive != next.active) { if (next.active) resume() else pause() }
        refresh()
    }

    private fun style(key: String, build: () -> LabelStyles): LabelStyles =
        styles.getOrPut(key) { map?.labelManager?.addLabelStyles(build()) ?: build() }

    private fun iconStyle(image: PinImage, zoomLevel: Int = 0): LabelStyle =
        LabelStyle.from(image.bitmap).setAnchorPoint(image.anchorX, image.anchorY).setApplyDpScale(false).setZoomLevel(zoomLevel)

    private fun layer(id: String): LabelLayer? = map?.labelManager?.getLayer(id)

    private fun latLng(c: CampusCoordinate) = LatLng.from(c.latitude, c.longitude)

    fun refresh() {
        val map = map ?: return
        val state = state ?: return
        // 현재 카드 높이만큼 지도 여백을 준다. 카메라 이동 전에 먼저 적용한다.
        val bottom = minOf(maxOf(0, state.bottomInsetPx), (map.viewport.height() * 0.65f).toInt())
        val top = maxOf(0, state.topObstructionPx)
        val marginsChanged = lastInsets != Pair(top, bottom)
        if (marginsChanged) {
            map.setPadding(0, top, 0, bottom)
            lastInsets = Pair(top, bottom)
        }
        refreshUserLocation(map, state)
        refreshShuttles()
        refreshAmenities(map, state)
        refreshTreasures(state)

        if (state.zoomRequest != lastZoomRequest) {
            val delta = state.zoomRequest - lastZoomRequest
            lastZoomRequest = state.zoomRequest
            val center = map.cameraPosition?.position
            val level = (map.zoomLevel + delta).coerceIn(7, 20)
            val update = if (center != null) CameraUpdateFactory.newCenterPosition(center, level) else CameraUpdateFactory.zoomTo(level)
            map.moveCamera(update, CameraAnimation.from(300))
        }

        val visible = state.places.map { it.id }.toSet()
        pinsVisible = map.zoomLevel >= MIN_PIN_LEVEL
        val places = layer(PLACES) ?: return
        for (p in Place.all) {
            if (p.type == PlaceType.HUB) continue // 예시 거점은 공식 센터가 아니어서 그리지 않는다.
            val isSel = state.selected == p.id
            val key = "${p.type}-${p.id}-$isSel"
            val labelStyles = style(key) {
                if (p.type == PlaceType.FOOD) {
                    // 식당 이름은 핀이 보이는 레벨(14~)부터 보인다. 선택된 핀은 항상 보인다.
                    val named = bitmaps.placePin(p.type, isSel, p.name)
                    if (isSel) LabelStyles.from(iconStyle(named))
                    else LabelStyles.from(iconStyle(bitmaps.placePin(p.type, false, null), 0), iconStyle(named, 14))
                } else {
                    LabelStyles.from(iconStyle(bitmaps.placePin(p.type, isSel, null))
                        .setTextStyles(LabelTextStyle.from((12 * density).toInt(), android.graphics.Color.BLACK, (2 * density).toInt(), android.graphics.Color.WHITE))
                        .setTextGravity(Gravity.END))
                }
            }
            val existing = placeLabels[p.id]
            if (existing == null) {
                val options = LabelOptions.from(p.id, LatLng.from(p.lat, p.lng)).setStyles(labelStyles).setRank(if (isSel) 100L else 0L).setClickable(true)
                if (isSel && p.type != PlaceType.FOOD) options.setTexts(LabelTextBuilder().setTexts(p.name))
                val label = places.addLabel(options) ?: continue
                placeLabels[p.id] = label
                placeStyle[p.id] = key
            } else if (placeStyle[p.id] != key) {
                if (p.type == PlaceType.FOOD) existing.changeStyles(labelStyles)
                else existing.changeStylesAndText(labelStyles, LabelTextBuilder().setTexts(if (isSel) p.name else ""))
                existing.setRank(if (isSel) 100L else 0L)
                placeStyle[p.id] = key
            }
            val label = placeLabels[p.id] ?: continue
            if (pinsVisible && p.id in visible) { if (!label.isShow) label.show() } else if (label.isShow) label.hide()
        }

        // 같은 지도 엔진을 재사용한다. 두 번째 지도를 만들지 않는다.
        if (lastBuildingID != state.focusedBuilding?.id) {
            lastBuildingID?.let { buildingLabels[it]?.hide() }
            state.focusedBuilding?.let { building ->
                val label = buildingLabels[building.id] ?: places.addLabel(
                    LabelOptions.from("campus-${building.id}", LatLng.from(building.latitude, building.longitude))
                        .setStyles(style("campus-building-focus") { LabelStyles.from(iconStyle(bitmaps.buildingPin())) })
                        .setRank(200L).setClickable(true),
                )?.also { buildingLabels[building.id] = it }
                label?.show()
            }
            lastBuildingID = state.focusedBuilding?.id
        }
        val building = state.focusedBuilding
        if (building != null && (state.focusSerial != lastFocusSerial || marginsChanged)) {
            map.moveCamera(CameraUpdateFactory.newCenterPosition(LatLng.from(building.latitude, building.longitude), maxOf(17, map.zoomLevel)),
                CameraAnimation.from(500))
            lastFocusSerial = state.focusSerial
        }

        if (lastSelected != state.selected) {
            if (lastSelected != null) Place.byID[state.selected]?.let { p ->
                map.moveCamera(CameraUpdateFactory.newCenterPosition(LatLng.from(p.lat, p.lng)), CameraAnimation.from(500))
            }
            lastSelected = state.selected
        }
    }

    private fun refreshAmenities(map: KakaoMap, state: CampusMapState) {
        val layer = layer(PLACES) ?: return
        val ids = state.amenityGroups.map { it.id }.toSet()
        for ((id, label) in amenityLabels) if (id !in ids || map.zoomLevel < MIN_PIN_LEVEL) label.hide()
        if (map.zoomLevel < MIN_PIN_LEVEL) return
        for (group in state.amenityGroups) {
            val first = group.amenities.firstOrNull() ?: continue
            val detailed = map.zoomLevel >= 17
            val key = "amenity-${group.id}-${first.kind}-${group.amenities.size}-$detailed"
            val labelStyles = style(key) {
                val name = if (detailed) (if (group.amenities.size == 1) first.name else group.building.name) else null
                LabelStyles.from(iconStyle(bitmaps.amenityPin(first.kind, group.amenities.size, name)))
            }
            val existing = amenityLabels[group.id]
            if (existing == null) {
                layer.addLabel(LabelOptions.from("amenity-building-${group.id}", latLng(group.building.coordinate))
                    .setStyles(labelStyles).setRank(150L).setClickable(true))?.let { amenityLabels[group.id] = it }
            } else if (amenityStyle[group.id] != key) {
                existing.changeStyles(labelStyles)
            }
            amenityStyle[group.id] = key
            amenityLabels[group.id]?.let { if (!it.isShow) it.show() }
        }
    }

    fun refreshShuttles() {
        val map = map ?: return
        val layer = layer(SHUTTLE) ?: return
        val positions = shuttle.positions
        val ids = positions.map { it.id }.toSet()
        for (id in shuttleLabels.keys.toList()) if (id !in ids) { shuttleLabels.remove(id)?.let { layer.remove(it) } }
        if (map.zoomLevel < MIN_SHUTTLE_LEVEL) { shuttleLabels.values.forEach { if (it.isShow) it.hide() }; return }
        val labelStyles = style("campus-circular-vehicle-small") { LabelStyles.from(iconStyle(bitmaps.shuttle())) }
        for (bus in positions) {
            val point = latLng(bus.coordinate)
            val label = shuttleLabels[bus.id] ?: layer.addLabel(
                LabelOptions.from("circular-${bus.id}", point).setStyles(labelStyles).setRank(400L)
                    .setClickable(false).setTransform(TransformMethod.AbsoluteRotation),
            )?.also { shuttleLabels[bus.id] = it } ?: continue
            label.moveTo(point)
            label.rotateTo(bus.bearingRadians.toFloat())
            if (!label.isShow) label.show()
        }
    }

    /** 반경 안 미발견 보물 자리에서 여우가 어슬렁거린다. */
    private fun refreshTreasures(state: CampusMapState) {
        val layer = layer(TREASURE) ?: return
        val ids = state.treasures.map { it.id }.toSet()
        for (id in treasureLabels.keys.toList()) if (id !in ids) { treasureLabels.remove(id)?.let { layer.remove(it) } }
        val labelStyles = style("treasure-fox") { LabelStyles.from(iconStyle(bitmaps.fox())) }
        for (treasure in state.treasures) {
            if (treasureLabels.containsKey(treasure.id)) continue
            layer.addLabel(LabelOptions.from("fox-${treasure.id}", latLng(treasure.coordinate)).setStyles(labelStyles).setRank(600L).setClickable(true))
                ?.let { it.show(); treasureLabels[treasure.id] = it }
        }
        if (treasureLabels.isEmpty()) {
            foxRunnable?.let { handler.removeCallbacks(it) }; foxRunnable = null
        } else if (foxRunnable == null) {
            val runnable = object : Runnable {
                override fun run() { wanderFoxes(); handler.postDelayed(this, 2600) }
            }
            foxRunnable = runnable
            handler.postDelayed(runnable, 2600)
        }
    }

    /** 보물 좌표 주변 약 12m 안의 아무 점으로 천천히 걸어간다. */
    private fun wanderFoxes() {
        val state = state ?: return
        for (treasure in state.treasures) {
            val label = treasureLabels[treasure.id] ?: continue
            val meters = Random.nextDouble(3.0, 12.0)
            val angle = Random.nextDouble(0.0, 2 * PI)
            val lat = treasure.coordinate.latitude + meters * cos(angle) / 111_000
            val lon = treasure.coordinate.longitude + meters * sin(angle) / (111_000 * cos(treasure.coordinate.latitude * PI / 180))
            label.moveTo(LatLng.from(lat, lon), 2400)
        }
    }

    private fun refreshUserLocation(map: KakaoMap, state: CampusMapState) {
        val layer = layer(USER)
        val coord = state.userCoordinate
        if (coord == null || !coord.isValid || layer == null) {
            userDot?.hide(); userDirection?.hide(); return
        }
        val point = latLng(coord)
        val dot = userDot ?: layer.addLabel(LabelOptions.from("my-location-dot", point)
            .setStyles(style("user-position-dot") { LabelStyles.from(iconStyle(bitmaps.userDot())) }).setRank(500L).setClickable(false))
            ?.also { userDot = it }
        dot?.moveTo(point); if (dot?.isShow == false) dot.show()
        val heading = state.userHeadingDegrees?.let { org.chargajoe.chajajwo.UserLocationMath.headingRadians(it) }
        if (heading != null) {
            val dir = userDirection ?: layer.addLabel(LabelOptions.from("my-location-direction", point)
                .setStyles(style("user-position-direction") { LabelStyles.from(iconStyle(bitmaps.userDirection())) })
                .setRank(499L).setClickable(false).setTransform(TransformMethod.AbsoluteRotation))
                ?.also { userDirection = it }
            dir?.moveTo(point); dir?.rotateTo(heading.toFloat()); if (dir?.isShow == false) dir.show()
        } else {
            userDirection?.hide() // 나침반이 없거나 부정확하면 점만
        }
        if (state.userFocusSerial != lastUserFocusSerial) {
            map.moveCamera(CameraUpdateFactory.newCenterPosition(point, 17), CameraAnimation.from(450))
            lastUserFocusSerial = state.userFocusSerial
        }
    }

    private fun labelTapped(label: Label) {
        val state = state ?: return
        val id = label.labelId ?: return
        lastLabelTapAt = SystemClock.uptimeMillis()
        callbacks.onTouch()
        when {
            id.startsWith("fox-") -> callbacks.onTreasureSelect(id.removePrefix("fox-"))
            id.startsWith("campus-") -> state.focusedBuilding?.takeIf { "campus-${it.id}" == id }?.let { selectBuilding(it) }
            id.startsWith("amenity-building-") -> state.amenityGroups.firstOrNull { "amenity-building-${it.id}" == id }?.let {
                lastBuildingTapAt = SystemClock.uptimeMillis()
                callbacks.onSelectAmenityBuilding(it.building)
            }
            state.places.any { it.id == id } -> callbacks.onSelect(id)
        }
    }

    private fun selectBuilding(building: CampusBuilding) {
        val now = SystemClock.uptimeMillis()
        if (building.id == lastBuildingTapID && now - lastBuildingTapAt <= 300) return
        lastBuildingTapAt = now
        lastBuildingTapID = building.id
        callbacks.onTouch()
        callbacks.onSelectBuilding(building)
    }

    /** 지도 기본 POI(건물 이름)를 오프라인 캠퍼스 카탈로그와 맞춘다. */
    private fun poiTapped(position: LatLng, layerId: String?) {
        if (layerId in listOf(PLACES, USER, SHUTTLE, TREASURE)) return
        val coordinate = CampusCoordinate(position.latitude, position.longitude)
        if (!coordinate.isValid) return
        val building = CampusBuildingCatalog.all.minByOrNull { it.coordinate.distanceTo(coordinate) } ?: return
        if (building.coordinate.distanceTo(coordinate) > 45) return
        selectBuilding(building)
    }

    private fun mapTapped(map: KakaoMap, position: LatLng, x: Float, y: Float) {
        callbacks.onTouch() // 지도를 누르면 키보드를 내린다.
        val state = state ?: return
        // 핀 탭이 지도 탭도 함께 보내므로 한 번만 처리한다.
        if (SystemClock.uptimeMillis() - maxOf(lastBuildingTapAt, lastLabelTapAt) < 250) return
        val radiusPx = 22 * density
        if (pinsVisible) {
            // 핀 끝이 좌표에 놓이므로 아이콘 몸통 중심으로 판정한다.
            val offset = 17 * 0.8f * density
            val hit = state.places.mapNotNull { place ->
                val pt = map.toScreenPoint(LatLng.from(place.lat, place.lng)) ?: return@mapNotNull null
                val dist = hypot(pt.x - x, pt.y - offset - y)
                if (dist <= radiusPx) place.id to dist else null
            }.minByOrNull { it.second }
            if (hit != null) { callbacks.onSelect(hit.first); return }
        }
        val coordinate = CampusCoordinate(position.latitude, position.longitude)
        val targets = CampusBuildingCatalog.all.mapNotNull { b ->
            val pt = map.toScreenPoint(LatLng.from(b.latitude, b.longitude)) ?: return@mapNotNull null
            CampusBuildingHitTest.Target(b.id, b.coordinate, pt.x.toFloat(), pt.y.toFloat())
        }
        val id = CampusBuildingHitTest.select(x, y, coordinate, map.zoomLevel, targets, density)
        val building = id?.let { bid -> CampusBuildingCatalog.all.firstOrNull { it.id == bid } }
        if (building != null) { selectBuilding(building); return }
        callbacks.onDeselect()
    }
}
