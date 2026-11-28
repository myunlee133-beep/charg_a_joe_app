package org.chargajoe.chajajwo.ui

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import org.chargajoe.chajajwo.Store
import org.chargajoe.chajajwo.UserLocationService
import org.chargajoe.chajajwo.data.CampusAmenities
import org.chargajoe.chajajwo.data.CampusAmenity
import org.chargajoe.chajajwo.data.CampusAmenityKind
import org.chargajoe.chajajwo.data.CampusBuilding
import org.chargajoe.chajajwo.data.CampusBuildingCatalog
import org.chargajoe.chajajwo.data.Landmark
import org.chargajoe.chajajwo.data.Place
import org.chargajoe.chajajwo.data.PlaceType
import org.chargajoe.chajajwo.ui.building.BuildingAmenityBadges
import org.chargajoe.chajajwo.ui.building.BuildingExplorerSheet
import org.chargajoe.chajajwo.ui.building.CampusAmenityRow
import org.chargajoe.chajajwo.ui.map.CampusMapCallbacks
import org.chargajoe.chajajwo.ui.map.CampusMapState
import org.chargajoe.chajajwo.ui.map.CampusMapView

@Composable
fun HomeScreen() {
    val app = LocalApp.current
    val store = app.store
    val context = LocalContext.current
    val density = LocalDensity.current
    val focusManager = LocalFocusManager.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val lifeState by lifecycle.currentStateAsState()
    val resumed = lifeState.isAtLeast(Lifecycle.State.RESUMED)

    var zoomRequest by remember { mutableIntStateOf(0) }
    var query by remember { mutableStateOf("") }
    var focusedBuilding by remember { mutableStateOf<CampusBuilding?>(null) }
    var exploredBuilding by remember { mutableStateOf<CampusBuilding?>(null) }
    var focusedAmenity by remember { mutableStateOf<CampusAmenity?>(null) }
    var browsingAmenities by remember { mutableStateOf(false) }
    var amenityKind by remember { mutableStateOf<CampusAmenityKind?>(null) }
    var buildingAmenityKind by remember { mutableStateOf<CampusAmenityKind?>(null) }
    var openVisitTasks by remember { mutableStateOf(false) }
    var pendingBuildingRoute by remember { mutableStateOf<CampusBuilding?>(null) }
    var buildingDirections by remember { mutableStateOf<BuildingDirectionsRequest?>(null) }
    var focusSerial by remember { mutableIntStateOf(0) }
    var userFocusSerial by remember { mutableIntStateOf(0) }
    var pendingUserFocus by remember { mutableStateOf(false) }
    var showLocationSettings by remember { mutableStateOf(false) }
    var placeSheet by remember { mutableStateOf(SheetDetent.NORMAL) }
    var bottomHeightPx by remember { mutableIntStateOf(0) }
    var topBarBottomPx by remember { mutableIntStateOf(0) }
    var mapHeightPx by remember { mutableIntStateOf(0) }
    var previewRoute by remember { mutableStateOf(false) }
    val searchFocus = remember { FocusRequester() }
    val userLocation = remember { UserLocationService(context.applicationContext) }
    val landmarkIDs = app.landmarks.ids

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        userLocation.onPermissionResult(result.values.any { it })
    }
    userLocation.requestPermission = {
        permissionLauncher.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
    }

    val homeActive = resumed && store.tab == Store.Tab.HOME
    DisposableEffect(homeActive) {
        if (homeActive) userLocation.start() else { userLocation.stop(); pendingUserFocus = false; focusManager.clearFocus() }
        onDispose { userLocation.stop(); pendingUserFocus = false }
    }

    val hasSearchText = query.isNotBlank()
    val searchResults = remember(query) { CampusBuildingCatalog.search(query, includeFacilityNames = false) }
    val amenityResults = remember(query) {
        val key = query.trim()
        if (key.all { it.isDigit() || it == '-' || it == '동' }) emptyList() else CampusAmenities.search(query)
    }
    val browsedAmenities = remember(amenityKind) { CampusAmenities.mapGroups(amenityKind).flatMap { it.amenities } }

    // 예시 거점 세 곳은 공식 센터가 아니므로 그리지 않는다.
    val places = if (store.lostMapOnly || browsingAmenities) emptyList() else Place.all.filter {
        when (store.homeFilter) {
            Store.HomeFilter.ALL -> it.type != PlaceType.HUB
            Store.HomeFilter.QUESTS, Store.HomeFilter.HUBS -> false
            Store.HomeFilter.FOOD -> it.type == PlaceType.FOOD
            Store.HomeFilter.SHUTTLE -> it.type == PlaceType.STOP
        }
    }
    val hereCoordinate = userLocation.coordinate
    val nearbyTreasures = hereCoordinate?.let { Landmark.nearby(it, landmarkIDs) } ?: emptyList()

    fun clearMapSelection() {
        focusedBuilding = null; focusedAmenity = null; store.closeSheet()
    }

    fun focus(building: CampusBuilding, preserveFilter: Boolean = false) {
        openVisitTasks = false
        focusManager.clearFocus()
        clearMapSelection()
        pendingUserFocus = false
        if (!preserveFilter) { store.filter = null; store.homeFilter = Store.HomeFilter.ALL; store.lostMapOnly = false }
        placeSheet = SheetDetent.NORMAL
        focusedBuilding = building
        focusedAmenity = null
        buildingAmenityKind = if (browsingAmenities) amenityKind else null
        focusSerial += 1 // 같은 건물을 다시 눌러도 카메라를 다시 맞춘다.
        query = ""       // 결과를 닫아 지도 위치가 잘 보이게 한다.
    }

    fun openAmenity(amenity: CampusAmenity) {
        focus(amenity.building, preserveFilter = true)
        focusedAmenity = amenity
        buildingAmenityKind = amenity.kind
        exploredBuilding = amenity.building
    }

    fun search() {
        val q = query.trim()
        focusManager.clearFocus()
        if (q.isEmpty()) return
        val buildings = searchResults
        when {
            amenityResults.size == 1 && buildings.isEmpty() -> openAmenity(amenityResults.first())
            amenityResults.isNotEmpty() -> return
            buildings.size == 1 -> focus(buildings.first())
            buildings.isNotEmpty() -> return // 다른 결과를 버리고 첫 번째로 뛰지 않는다.
            else -> {
                val p = Place.all.firstOrNull { it.type != PlaceType.HUB && it.name.contains(q, ignoreCase = true) }
                if (p != null) {
                    focusedBuilding = null; query = ""; store.filter = null; store.homeFilter = Store.HomeFilter.ALL
                    store.lostMapOnly = false; store.select(p.id)
                } else store.toast("'$q' 검색 결과가 없어요")
            }
        }
    }

    fun focusMyLocation() {
        focusManager.clearFocus()
        if (userLocation.authorization == UserLocationService.Authorization.DENIED) { showLocationSettings = true; return }
        userLocation.start()
        if (userLocation.coordinate != null) {
            pendingUserFocus = false; focusedBuilding = null; store.closeSheet(); userFocusSerial += 1
        } else {
            pendingUserFocus = true
            store.toast(userLocation.errorMessage ?: "현재 위치를 확인하고 있어요")
        }
    }

    LaunchedEffect(userLocation.coordinate?.latitude) {
        if (pendingUserFocus && userLocation.coordinate != null) {
            pendingUserFocus = false; focusedBuilding = null; store.closeSheet(); userFocusSerial += 1
        }
    }
    LaunchedEffect(store.sel, store.open) { if (store.open) focusedBuilding = null }
    val placeSheetKey = "${focusedBuilding?.id ?: ""}|${if (store.open) store.sel else ""}"
    LaunchedEffect(placeSheetKey) { placeSheet = SheetDetent.NORMAL }
    LaunchedEffect(store.pendingVisitSerial) {
        val id = store.pendingVisitBuildingID ?: return@LaunchedEffect
        val building = CampusBuildingCatalog.all.firstOrNull { it.id == id } ?: return@LaunchedEffect
        store.pendingVisitBuildingID = null
        store.tab = Store.Tab.HOME; store.showDining = false
        focus(building, preserveFilter = true)
        exploredBuilding = building
        openVisitTasks = true
    }
    LaunchedEffect(Unit) {
        when (val arg = store.previewArgument) {
            null -> Unit
            "directions" -> buildingDirections = BuildingDirectionsRequest(
                CampusBuildingCatalog.search("학생회관").firstOrNull(), CampusBuildingCatalog.search("중앙도서관").firstOrNull())
            "amenities" -> browsingAmenities = true
            "food" -> store.homeFilter = Store.HomeFilter.FOOD
            "route" -> previewRoute = true
            else -> if (arg.startsWith("building:")) {
                val number = arg.removePrefix("building:").substringBefore(":")
                CampusBuildingCatalog.all.firstOrNull { it.number == number }?.let {
                    focus(it, preserveFilter = true)
                    if (arg.endsWith(":explore")) exploredBuilding = it
                }
            } else if (arg.startsWith("place:")) store.select(arg.removePrefix("place:"))
        }
    }

    val mapState = CampusMapState(
        places = places,
        selected = if (store.open) store.sel else "",
        bottomInsetPx = bottomHeightPx,
        topObstructionPx = if (focusedBuilding == null) 0 else topBarBottomPx + with(density) { 12.dp.roundToPx() },
        focusedBuilding = focusedBuilding,
        focusSerial = focusSerial,
        userCoordinate = userLocation.coordinate,
        userHeadingDegrees = userLocation.headingDegrees,
        userFocusSerial = userFocusSerial,
        treasures = nearbyTreasures,
        zoomRequest = zoomRequest,
        amenityGroups = if (browsingAmenities) CampusAmenities.mapGroups(amenityKind) else emptyList(),
        active = homeActive,
    )
    val callbacks = remember {
        CampusMapCallbacks(
            onTreasureSelect = { store.toast("AR 보물찾기는 다음 업데이트에서 연결돼요") },
            onSelectAmenityBuilding = { focus(it, preserveFilter = true) },
            onDeselect = { clearMapSelection() },
            onSelectBuilding = { focus(it, preserveFilter = true) },
            onSelect = { id -> focusManager.clearFocus(); focusedBuilding = null; store.select(id) },
            onTouch = { focusManager.clearFocus() },
        )
    }

    Box(Modifier.fillMaxSize().onGloballyPositioned { mapHeightPx = it.size.height }) {
        CampusMapView(mapState, callbacks, app.shuttle, Modifier.fillMaxSize())

        // 상단 바
        Column(
            Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars).padding(horizontal = 16.dp).padding(top = 8.dp)
                .onGloballyPositioned { topBarBottomPx = (it.positionInParent().y + it.size.height).toInt() },
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    Modifier.background(Cj.surface.copy(alpha = 0.95f), RoundedCornerShape(14.dp)).padding(start = 4.dp, end = 12.dp, top = 4.dp, bottom = 4.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box(Modifier.size(34.dp).background(Cj.teal, RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
                        SymbolIcon(Sym.search, Color.White, 19.dp)
                    }
                    Text("찾아줘", style = Type.title3.w(FontWeight.ExtraBold))
                }
                Spacer(Modifier.weight(1f))
                Row(
                    Modifier.height(42.dp).background(Cj.surface.copy(alpha = 0.95f), RoundedCornerShape(14.dp))
                        .tap { store.toast("보물 도감과 AR 보물찾기는 다음 업데이트에서 연결돼요") }.padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    SymbolIcon(Sym.box, Cj.tealText, 17.dp)
                    Text("${landmarkIDs.size}/${Landmark.all.size}", style = Type.subheadline.w(FontWeight.Bold), color = Cj.tealText)
                }
                Row(
                    Modifier.heightIn(min = 44.dp).background(Cj.surface, RoundedCornerShape(14.dp))
                        .tap { focusManager.clearFocus(); buildingDirections = BuildingDirectionsRequest() }.padding(horizontal = 14.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    SymbolIcon(Sym.directionsFill, Cj.tealText, 18.dp)
                    Text("길찾기", style = Type.subheadline.w(FontWeight.SemiBold), color = Cj.tealText)
                }
            }

            Row(
                Modifier.fillMaxWidth().height(48.dp).shadow(4.dp, RoundedCornerShape(14.dp)).background(Cj.surface, RoundedCornerShape(14.dp))
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                SymbolIcon(Sym.search, Color.Black, 19.dp)
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                    if (query.isEmpty()) Text("건물·카페·편의점·약국 검색", style = Type.body, color = hex(0x3C3C43).copy(alpha = 0.3f), maxLines = 1)
                    BasicTextField(
                        value = query,
                        onValueChange = { query = it; if (it.isNotEmpty()) focusedBuilding = null },
                        singleLine = true,
                        textStyle = Type.body.copy(color = Color.Black),
                        cursorBrush = SolidColor(Cj.teal),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(onSearch = { search() }),
                        modifier = Modifier.fillMaxWidth().focusRequester(searchFocus),
                    )
                }
                if (hasSearchText) SymbolIcon(Sym.xmarkCircle, Cj.sub, 20.dp, Modifier.tap { query = "" }, "검색어 지우기")
            }

            if (hasSearchText) SearchResultsPanel(searchResults, amenityResults, onAmenity = { openAmenity(it) }, onBuilding = { focus(it) })

            Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                @Composable
                fun chip(title: String, icon: ImageVector, filter: Store.HomeFilter) {
                    val on = !browsingAmenities && !store.lostMapOnly && store.homeFilter == filter
                    MapChip(title, icon, on) {
                        browsingAmenities = false; amenityKind = null; focusedAmenity = null
                        store.lostMapOnly = false
                        store.homeFilter = filter
                        store.closeSheet()
                        focusedBuilding = null
                    }
                }
                chip("전체", Sym.grid, Store.HomeFilter.ALL)
                chip("식당", Sym.forkKnife, Store.HomeFilter.FOOD)
                MapChip("편의시설", Sym.basket, browsingAmenities) {
                    browsingAmenities = !browsingAmenities; amenityKind = null
                    focusedBuilding = null; focusedAmenity = null; query = ""; focusManager.clearFocus()
                    store.closeSheet(); store.lostMapOnly = false; store.homeFilter = Store.HomeFilter.ALL
                }
                chip("셔틀", Sym.bus, Store.HomeFilter.SHUTTLE)
            }
        }

        // 내 위치·확대/축소 버튼: 지금 떠 있는 하단 시트 바로 위
        val bottomDp = with(density) { bottomHeightPx.toDp() }
        val clearHeight = with(density) { (mapHeightPx - topBarBottomPx - bottomHeightPx).toDp() }
        val compact = mapHeightPx > 0 && clearHeight < 210.dp
        Column(
            Modifier.align(Alignment.BottomEnd).padding(end = 16.dp, bottom = bottomDp + 16.dp),
            horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            if (userLocation.approximateLocation && userLocation.coordinate != null) {
                Text("대략적인 위치", style = Type.caption2.w(FontWeight.SemiBold), color = hex(0x182A30),
                    modifier = Modifier.background(Color.White, CircleShape).padding(horizontal = 9.dp, vertical = 5.dp))
            }
            MapControls(compact, onZoomIn = { zoomRequest += 1 }, onZoomOut = { zoomRequest -= 1 },
                located = userLocation.coordinate != null, onLocate = { focusMyLocation() })
        }

        // 하단 시트(칩으로 거른 지도에는 띄우지 않는다. 핀을 누르면 그 핀의 시트가 뜬다.)
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().onGloballyPositioned { bottomHeightPx = it.size.height }) {
            val building = focusedBuilding
            val selectedPlace = Place.byID[store.sel]
            when {
                building != null -> BuildingCard(building, placeSheet, { placeSheet = it },
                    onClose = { focusedBuilding = null },
                    onExplore = { kind -> buildingAmenityKind = kind; exploredBuilding = building })
                browsingAmenities -> AmenityBrowser(placeSheet, { placeSheet = it }, amenityKind, { amenityKind = it }, browsedAmenities,
                    onClose = { browsingAmenities = false }, onOpen = { openAmenity(it) })
                store.open && selectedPlace?.type == PlaceType.STOP -> HomePlaceCard(selectedPlace, placeSheet) { placeSheet = it }
                store.open -> SheetView(placeSheet) { placeSheet = it }
            }
        }
    }

    exploredBuilding?.let { building ->
        BuildingExplorerSheet(
            building = building,
            onRestaurant = { place ->
                exploredBuilding = null
                browsingAmenities = false
                clearMapSelection()
                store.select(place.id)
            },
            onDirections = { pendingBuildingRoute = building; exploredBuilding = null },
            showTasksOnOpen = openVisitTasks,
            initialKind = buildingAmenityKind,
            initialAmenity = focusedAmenity,
            onDismiss = {
                exploredBuilding = null
                openVisitTasks = false
                focusedAmenity = null
            },
        )
    }
    LaunchedEffect(exploredBuilding, pendingBuildingRoute) {
        val route = pendingBuildingRoute
        if (exploredBuilding == null && route != null) {
            pendingBuildingRoute = null
            buildingDirections = BuildingDirectionsRequest(destination = route)
        }
    }

    buildingDirections?.let { request ->
        FullScreenDialog(onDismiss = { buildingDirections = null }) {
            BuildingDirectionsScreen(request.origin, request.destination, onClose = { buildingDirections = null })
        }
    }

    if (previewRoute) {
        val start = CampusBuildingCatalog.search("학생회관").firstOrNull()
        val end = CampusBuildingCatalog.search("중앙도서관").firstOrNull()
        val url = if (start != null && end != null) org.chargajoe.chajajwo.data.DirectionsURL.route(start.directionsEndpoint, end.directionsEndpoint) else null
        if (url != null) FullScreenDialog(onDismiss = { previewRoute = false }) {
            DirectionsScreen(url, "학생회관 → 중앙도서관", onClose = { previewRoute = false })
        }
    }

    if (showLocationSettings) {
        AlertDialog(
            onDismissRequest = { showLocationSettings = false },
            title = { Text("위치 접근 권한이 필요해요") },
            text = { Text("현재 위치를 지도에 표시하려면 휴대폰 설정에서 찾아줘의 위치 접근을 허용해주세요.") },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    showLocationSettings = false
                    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }) { Text("설정 열기") }
            },
            dismissButton = { androidx.compose.material3.TextButton(onClick = { showLocationSettings = false }) { Text("취소") } },
        )
    }
}

data class BuildingDirectionsRequest(val origin: CampusBuilding? = null, val destination: CampusBuilding? = null)

@Composable
private fun MapChip(title: String, icon: ImageVector, on: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.heightIn(min = 44.dp).shadow(3.dp, CircleShape).background(if (on) Cj.teal else Cj.surface, CircleShape)
            .tap(onClick = onClick).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        SymbolIcon(icon, if (on) Color.White else Color.Black, 17.dp)
        Text(title, style = Type.subheadline.w(FontWeight.Medium), color = if (on) Color.White else Color.Black)
    }
}

/** 표준 지도 앱의 내 위치 버튼. GPS는 계속 표시하되 카메라는 누를 때만 옮긴다. */
@Composable
private fun MapControls(compact: Boolean, onZoomIn: () -> Unit, onZoomOut: () -> Unit, located: Boolean, onLocate: () -> Unit) {
    @Composable
    fun zoomButton(icon: ImageVector, label: String, onClick: () -> Unit) {
        Box(Modifier.size(44.dp).tap(onClick = onClick), contentAlignment = Alignment.Center) {
            SymbolIcon(icon, Cj.tealText, 20.dp, contentDescription = label)
        }
    }
    @Composable
    fun zoomGroup() {
        val modifier = Modifier.shadow(4.dp, RoundedCornerShape(12.dp)).background(Color.White, RoundedCornerShape(12.dp))
        if (compact) Row(modifier, verticalAlignment = Alignment.CenterVertically) {
            zoomButton(Sym.plus, "지도 확대", onZoomIn)
            Box(Modifier.width(0.5.dp).height(28.dp).background(Cj.line))
            zoomButton(Sym.minus, "지도 축소", onZoomOut)
        } else Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
            zoomButton(Sym.plus, "지도 확대", onZoomIn)
            Box(Modifier.width(28.dp).height(0.5.dp).background(Cj.line))
            zoomButton(Sym.minus, "지도 축소", onZoomOut)
        }
    }
    @Composable
    fun locate() {
        Box(
            Modifier.size(52.dp).shadow(7.dp, CircleShape).background(Color.White, CircleShape).border(1.dp, hex(0xDDE7E8), CircleShape).tap(onClick = onLocate),
            contentAlignment = Alignment.Center,
        ) { SymbolIcon(if (located) Sym.locationFill else Sym.location, hex(0x287AF0), 24.dp, contentDescription = "내 위치로 이동") }
    }
    if (compact) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) { zoomGroup(); locate() }
    else Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(10.dp)) { zoomGroup(); locate() }
}

/** 지도 위에서도 대비가 높게 보이도록 결과 패널은 항상 흰색이다. */
private object SearchResultColors {
    val background = Color.White
    val title = hex(0x182A30)
    val secondary = hex(0x4A6067)
    val accent = hex(0x0D7569)
    val separator = hex(0xDDE7E8)
}

@Composable
private fun SearchResultsPanel(buildings: List<CampusBuilding>, amenities: List<CampusAmenity>, onAmenity: (CampusAmenity) -> Unit, onBuilding: (CampusBuilding) -> Unit) {
    Column(Modifier.fillMaxWidth().shadow(5.dp, RoundedCornerShape(14.dp)).background(SearchResultColors.background, RoundedCornerShape(14.dp))) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp)) {
            Text("검색 결과 ${buildings.size + amenities.size}개", style = Type.caption.w(FontWeight.Bold), color = SearchResultColors.secondary)
            Spacer(Modifier.weight(1f))
            Text("시설·건물 상세 보기", style = Type.caption2, color = SearchResultColors.secondary)
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(SearchResultColors.separator))
        if (buildings.isEmpty() && amenities.isEmpty()) {
            Text(if (CampusBuildingCatalog.all.isEmpty()) "건물 데이터를 불러오지 못했어요" else "일치하는 건물이나 장소가 없어요",
                style = Type.subheadline, color = SearchResultColors.secondary, modifier = Modifier.padding(16.dp))
        } else {
            val height: Dp = minOf(320.dp, (amenities.size * 100 + buildings.size * 66 +
                ((if (amenities.isEmpty()) 0 else 1) + (if (buildings.isEmpty()) 0 else 1)) * 38).dp)
            LazyColumn(Modifier.fillMaxWidth().height(height)) {
                if (amenities.isNotEmpty()) {
                    item { SearchSectionTitle("시설", amenities.size) }
                    items(amenities, key = { "a-" + it.id }) { amenity ->
                        Box(Modifier.tap { onAmenity(amenity) }) { CampusAmenityRow(amenity, showBuilding = true) }
                        Divider(Modifier.padding(start = 66.dp))
                    }
                }
                if (buildings.isNotEmpty()) item { SearchSectionTitle("건물", buildings.size) }
                items(buildings, key = { "b-" + it.id }) { building ->
                    Row(Modifier.fillMaxWidth().tap { onBuilding(building) }.padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        SymbolIcon(Sym.building, SearchResultColors.accent, 20.dp, Modifier.width(25.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(building.name, style = Type.subheadline.w(FontWeight.SemiBold), color = SearchResultColors.title)
                            Text(building.buildingNumberLabel, style = Type.caption, color = SearchResultColors.secondary)
                        }
                        SymbolIcon(Sym.locationFill, SearchResultColors.accent, 17.dp)
                    }
                    Box(Modifier.fillMaxWidth().padding(start = 48.dp).height(1.dp).background(SearchResultColors.separator))
                }
            }
        }
    }
}

@Composable
private fun SearchSectionTitle(name: String, count: Int) {
    Row(Modifier.fillMaxWidth().background(hex(0xf5f8f6)).padding(horizontal = 14.dp, vertical = 9.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(name, style = Type.caption.w(FontWeight.Bold), color = SearchResultColors.secondary)
        Text("$count", style = Type.caption, color = SearchResultColors.secondary)
    }
}

@Composable
private fun BuildingCard(building: CampusBuilding, detent: SheetDetent, onDetent: (SheetDetent) -> Unit, onClose: () -> Unit, onExplore: (CampusAmenityKind?) -> Unit) {
    SwipeSheet(detent, onDetent, header = {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(building.buildingNumberLabel, style = Type.caption.w(FontWeight.Bold), color = BuildingDesign.green)
                Text(building.name, style = Type.headline)
                building.details?.englishName?.let { Text(it, style = Type.caption, color = Cj.sub) }
            }
            Box(Modifier.size(44.dp).tap(onClick = onClose), contentAlignment = Alignment.Center) {
                SymbolIcon(Sym.xmarkCircle, Cj.sub, 26.dp, contentDescription = "건물 상세정보 닫기")
            }
        }
    }) {
        BuildingAmenityBadges(building) { kind -> onExplore(kind) }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.weight(1f).heightIn(min = 48.dp).background(Cj.teal, RoundedCornerShape(12.dp)).tap { onExplore(null) },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                SymbolIcon(Sym.layers, Color.White, 18.dp); HSpacer(6.dp)
                Text("건물 상세", style = Type.subheadline.w(FontWeight.SemiBold), color = Color.White)
            }
            building.directionsURL?.let { url ->
                DirectionsButton(url, building.name) {
                    Row(Modifier.width(110.dp).heightIn(min = 48.dp).background(Cj.inset, RoundedCornerShape(12.dp)),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                        SymbolIcon(Sym.directions, Cj.tealText, 18.dp); HSpacer(6.dp)
                        Text("길찾기", style = Type.subheadline.w(FontWeight.SemiBold), color = Cj.tealText)
                    }
                }
            }
        }
    }
}

@Composable
private fun AmenityBrowser(
    detent: SheetDetent, onDetent: (SheetDetent) -> Unit, kind: CampusAmenityKind?, onKind: (CampusAmenityKind?) -> Unit,
    amenities: List<CampusAmenity>, onClose: () -> Unit, onOpen: (CampusAmenity) -> Unit,
) {
    SwipeSheet(detent, onDetent, header = {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("캠퍼스 편의시설", style = Type.headline)
                Text("건물과 층까지 한눈에", style = Type.caption, color = Cj.secondary)
            }
            Box(Modifier.size(44.dp).tap(onClick = onClose), contentAlignment = Alignment.Center) {
                SymbolIcon(Sym.xmark, Cj.tealText, 20.dp, contentDescription = "편의시설 목록 닫기")
            }
        }
    }) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CapsuleChip("전체", kind == null, BuildingDesign.green) { onKind(null) }
            CampusAmenityKind.everyday.forEach { item -> CapsuleChip(item.title, kind == item, BuildingDesign.green) { onKind(item) } }
        }
        LazyColumn(Modifier.fillMaxWidth().height(if (detent == SheetDetent.EXPANDED) 380.dp else 190.dp)) {
            items(amenities, key = { it.id }) { amenity ->
                Box(Modifier.tap { onOpen(amenity) }) { CampusAmenityRow(amenity, showBuilding = true) }
                Divider(Modifier.padding(start = 66.dp))
            }
        }
        Text("${amenities.size}곳 · 지도 표시는 시설이 있는 건물 위치예요", style = Type.caption, color = Cj.secondary)
    }
}

