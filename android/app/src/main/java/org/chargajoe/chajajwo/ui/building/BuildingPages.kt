package org.chargajoe.chajajwo.ui.building

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.kakao.vectormap.KakaoMap
import com.kakao.vectormap.KakaoMapReadyCallback
import com.kakao.vectormap.LatLng
import com.kakao.vectormap.MapLifeCycleCallback
import com.kakao.vectormap.MapView
import com.kakao.vectormap.camera.CameraUpdateFactory
import com.kakao.vectormap.label.LabelOptions
import com.kakao.vectormap.label.LabelStyle
import com.kakao.vectormap.label.LabelStyles
import org.chargajoe.chajajwo.data.CampusAmenities
import org.chargajoe.chajajwo.data.CampusBuilding
import org.chargajoe.chajajwo.data.CampusBuildingCatalog
import org.chargajoe.chajajwo.data.CampusPlanning
import org.chargajoe.chajajwo.data.CampusSpace
import org.chargajoe.chajajwo.data.Place
import org.chargajoe.chajajwo.data.PlaceDirectory
import org.chargajoe.chajajwo.data.PlaceType
import org.chargajoe.chajajwo.data.ResearchLab
import org.chargajoe.chajajwo.ui.AssetImage
import org.chargajoe.chajajwo.ui.BuildingDesign
import org.chargajoe.chajajwo.ui.BuildingDirectionsScreen
import org.chargajoe.chajajwo.ui.BuildingEmptyCard
import org.chargajoe.chajajwo.ui.BuildingSurface
import org.chargajoe.chajajwo.ui.CapsuleChip
import org.chargajoe.chajajwo.ui.Cj
import org.chargajoe.chajajwo.ui.ContentUnavailable
import org.chargajoe.chajajwo.ui.DirectionsButton
import org.chargajoe.chajajwo.ui.Disclosure
import org.chargajoe.chajajwo.ui.Divider
import org.chargajoe.chajajwo.ui.GroupRow
import org.chargajoe.chajajwo.ui.GroupSection
import org.chargajoe.chajajwo.ui.LabelText
import org.chargajoe.chajajwo.ui.LinkText
import org.chargajoe.chajajwo.ui.LocalApp
import org.chargajoe.chajajwo.ui.LocalNavigator
import org.chargajoe.chajajwo.ui.PlaceSourceLink
import org.chargajoe.chajajwo.ui.SearchField
import org.chargajoe.chajajwo.ui.SegmentedPicker
import org.chargajoe.chajajwo.ui.Sym
import org.chargajoe.chajajwo.ui.SymbolIcon
import org.chargajoe.chajajwo.ui.TopicFlowLayout
import org.chargajoe.chajajwo.ui.Type
import org.chargajoe.chajajwo.ui.map.PinBitmaps
import org.chargajoe.chajajwo.ui.map.PinPainters
import org.chargajoe.chajajwo.ui.tap
import org.chargajoe.chajajwo.ui.w
import kotlin.math.roundToInt

// MARK: 층별 공간 · 연구실 · 이용 안내

@Composable
fun BuildingFloorView(building: CampusBuilding) {
    val nav = LocalNavigator.current
    val floors = remember(building.id) { PlaceDirectory.floors(building) }
    var floor by remember { mutableStateOf(floors.firstOrNull() ?: "층 정보 미등록") }
    var query by remember { mutableStateOf("") }
    val searching = query.isNotBlank()
    val labs = PlaceDirectory.labs(building).filter { (searching || it.floor == floor) && PlaceDirectory.matches(query, it.searchFields) }
    val facilities = CampusAmenities.inBuilding(building).filter { (searching || it.floor == floor) && PlaceDirectory.matches(query, it.searchFields) }

    Column(Modifier.fillMaxSize().background(Cj.grouped)) {
        SearchField(query, { query = it }, "연구실·지도교수·연구분야", Modifier.padding(horizontal = 16.dp, vertical = 8.dp), background = Color.White, height = 38.dp)
        if (!searching) {
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                floors.forEach { value ->
                    val on = floor == value
                    Text(value, style = Type.subheadline.w(FontWeight.SemiBold), color = if (on) Color.White else Color.Black,
                        modifier = Modifier.background(if (on) Cj.tealText else Color.White, CircleShape).tap { floor = value }.padding(horizontal = 16.dp, vertical = 12.dp))
                }
            }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            if (searching) GroupSection { GroupRow(showDivider = false) { Text("건물 전체에서 검색 중", style = Type.caption, color = Cj.secondary) } }
            if (labs.isNotEmpty()) GroupSection("연구실 · ${labs.size}곳") {
                labs.forEachIndexed { i, lab ->
                    GroupRow(onClick = { nav?.push("연구실") { ResearchLabView(lab) } }, chevron = true, showDivider = i != labs.lastIndex) {
                        Column(Modifier.weight(1f).padding(vertical = 7.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                            Text(lab.name, style = Type.headline)
                            Text("지도교수 ${lab.professor} · ${lab.field}", style = Type.subheadline, color = Cj.secondary)
                            if (searching) Text(lab.floor, style = Type.caption, color = Cj.tealText)
                        }
                    }
                }
            }
            if (facilities.isNotEmpty()) GroupSection("등록 시설 · ${facilities.size}곳") {
                facilities.forEachIndexed { i, facility ->
                    Box(Modifier.tap { nav?.push("시설 상세") { CampusAmenityDetailView(facility) } }) { CampusAmenityRow(facility) }
                    if (i != facilities.lastIndex) Divider(Modifier.padding(start = 66.dp))
                }
            }
            if (labs.isEmpty() && facilities.isEmpty()) {
                ContentUnavailable(if (searching) "검색 결과가 없어요" else "등록된 공간이 없어요", Sym.building,
                    if (searching) "연구실 이름, 지도교수 또는 연구분야로 검색해 보세요." else "다른 층을 선택해 보세요.")
            }
            GroupSection(footer = "연구실은 컴퓨터공학부 공식 자료를 수록했어요. 일부 연구실·시설의 정보는 아직 등록되지 않았어요.")
        }
    }
}

@Composable
fun ResearchLabView(lab: ResearchLab) {
    Column(Modifier.fillMaxSize().background(Color.White).verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(32.dp)) {
        Text(lab.name, style = Type.largeTitle)
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("지도교수", style = Type.subheadline, color = Cj.secondary)
            Text(lab.professor + " 교수", style = Type.title2.w(FontWeight.SemiBold))
        }
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("주요 연구분야", style = Type.subheadline, color = Cj.secondary)
            TopicFlowLayout(8.dp) {
                lab.topics.forEach { topic ->
                    Text(topic, style = Type.subheadline.w(FontWeight.Medium),
                        modifier = Modifier.background(Cj.tealText.copy(alpha = 0.08f), CircleShape).padding(horizontal = 13.dp, vertical = 10.dp))
                }
            }
        }
        Divider()
        Disclosure(label = { expanded ->
            Text(if (expanded) "연구실 설명 접기" else "연구실 설명 펼쳐보기", style = Type.subheadline.w(FontWeight.SemiBold), color = Cj.tealText,
                modifier = Modifier.padding(vertical = 12.dp))
        }) {
            Column(Modifier.padding(top = 18.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Text(lab.summary, style = Type.body)
                LabelText(lab.room, Sym.pinEllipse, Type.subheadline)
                if (lab.floorDerived) Text("층 표시는 공식 호실 번호를 기준으로 분류했어요.", style = Type.caption, color = Cj.secondary)
                PlaceDirectory.phoneURL(lab.phone)?.let { LinkText(lab.phone, it) }
                PlaceSourceLink("연구실 공식 소개", lab.url)
                PlaceSourceLink("지도교수 소개", lab.professorURL)
                Text("공식 자료 확인 · ${lab.checkedAt}", style = Type.caption, color = Cj.secondary)
            }
        }
    }
}

@Composable
fun BuildingGuideView(building: CampusBuilding, onDirections: () -> Unit) {
    Column(Modifier.fillMaxSize().background(Cj.grouped).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        GroupSection("위치 정보") {
            GroupRow { Text(building.displayTitle, style = Type.body) }
            building.details?.address?.let { GroupRow { Text(it, style = Type.subheadline) } }
            building.directionsURL?.let { url ->
                DirectionsButton(url, building.name) { GroupRow { LabelText("여기로 길찾기", Sym.directions, Type.body, Cj.tealText) } }
            }
            GroupRow(onClick = onDirections) { LabelText("건물 간 길찾기", Sym.route, Type.body, Cj.tealText) }
            GroupRow(showDivider = false) { LinkText("카카오맵에서 위치 보기", building.mapURL) }
        }
        building.details?.let { details ->
            GroupSection("건물 소개") { GroupRow(showDivider = false) { Text(details.summary, style = Type.body) } }
            GroupSection("이용 안내") {
                GroupRow(showDivider = details.phone != null || details.websiteURL != null) { Text(details.usage, style = Type.body) }
                val phoneURL = details.phoneURL
                if (details.phone != null && phoneURL != null) GroupRow(showDivider = details.websiteURL != null) { LinkText(details.phone, phoneURL) }
                details.websiteURL?.let { GroupRow(showDivider = false) { LinkText("운영기관 홈페이지", it) } }
            }
            if (details.accessibility.isNotEmpty()) GroupSection("등록된 접근성 정보") {
                details.accessibility.forEachIndexed { i, it -> GroupRow(showDivider = i != details.accessibility.lastIndex) { Text(it, style = Type.body) } }
            }
            if (details.notices.isNotEmpty()) GroupSection("공식 안내") {
                details.notices.forEachIndexed { i, notice ->
                    GroupRow(showDivider = i != details.notices.lastIndex) {
                        Column(Modifier.padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(notice.title, style = Type.headline)
                            Text(notice.body, style = Type.subheadline)
                            LinkText("원문 확인", notice.sourceURL)
                            Text("확인 · ${notice.checkedAt}", style = Type.caption, color = Cj.secondary)
                        }
                    }
                }
            }
            GroupSection("정보 출처") {
                details.sources.forEachIndexed { i, source ->
                    GroupRow(showDivider = i != details.sources.lastIndex) {
                        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                            LinkText(source.title, source.url)
                            Text("확인 · ${source.checkedAt}", style = Type.caption, color = Cj.secondary)
                        }
                    }
                }
            }
        }
        if (building.source == "openstreetmap") GroupSection {
            GroupRow(showDivider = false) { PlaceSourceLink("지도 좌표 © OpenStreetMap contributors", "https://www.openstreetmap.org/copyright") }
        }
    }
}

// MARK: 식당·카페 · 시설 현황 · 내부 공간 · 공강 공간 · 일정 동선

private fun restaurants(building: CampusBuilding): List<Place> =
    Place.all.filter { it.type == PlaceType.FOOD && it.building == building.buildingNumberLabel }

@Composable
fun BuildingFoodCards(building: CampusBuilding, onRestaurant: (Place) -> Unit) {
    val nav = LocalNavigator.current
    val dining = LocalApp.current.store.dining
    var filter by remember { mutableStateOf("전체") }
    val restaurants = remember(building.id) { restaurants(building) }
    val venues = remember(building.id) { PlaceDirectory.venues(building) }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SegmentedPicker(listOf("전체", "식당", "카페"), filter, { it }) { filter = it }
        if (filter != "카페") restaurants.forEach { restaurant ->
            Box(Modifier.tap { onRestaurant(restaurant) }) {
                BuildingSurface {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(13.dp)) {
                        Box(Modifier.width(48.dp).height(58.dp).background(BuildingDesign.mint, RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
                            SymbolIcon(Sym.forkKnife, BuildingDesign.green, 26.dp)
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(restaurant.name, style = Type.headline)
                            Text(dining.hours(restaurant, System.currentTimeMillis()), style = Type.caption, color = Cj.secondary)
                            Text("오늘의 식단 보기", style = Type.caption.w(FontWeight.Medium), color = BuildingDesign.green)
                        }
                        SymbolIcon(Sym.chevronRight, Cj.secondary, 16.dp)
                    }
                }
            }
        }
        if (filter != "식당") venues.forEach { venue ->
            Box(Modifier.tap { nav?.push("카페 메뉴") { CafeMenuView(venue) } }) {
                BuildingSurface {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(13.dp)) {
                        val name = PlaceDirectory.imageName(venue.featuredMenu?.photoAsset ?: venue.photoAsset)
                        if (name != null) AssetImage(name, Modifier.width(65.dp).height(74.dp).background(Color.White, RoundedCornerShape(12.dp)))
                        else Box(Modifier.width(48.dp).height(58.dp).background(BuildingDesign.mint, RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
                            SymbolIcon(Sym.cupOutline, BuildingDesign.green, 26.dp)
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(venue.name, style = Type.headline)
                            Text("${venue.floor} · 평일 ${venue.weekdayHours}", style = Type.caption, color = Cj.secondary)
                            Text("메뉴 사진·상세 보기", style = Type.caption.w(FontWeight.Medium), color = BuildingDesign.green)
                        }
                        SymbolIcon(Sym.chevronRight, Cj.secondary, 16.dp)
                    }
                }
            }
        }
        if (restaurants.isEmpty() && venues.isEmpty()) BuildingEmptyCard(Sym.cupOutline, "등록된 매장 정보가 없어요", "교내 카페 전체 목록에서 다른 공간을 찾아보세요.")
        Text("교내 카페 전체 보기  ›", style = Type.subheadline.w(FontWeight.SemiBold), color = Cj.tealText,
            modifier = Modifier.heightIn(min = 44.dp).tap { nav?.push("교내 카페") { CafeDirectoryView() } }.padding(vertical = 12.dp))
        LabelText("혼잡도·좌석 현황은 아직 연결되지 않았어요.", Sym.info, Type.caption, Cj.secondary)
    }
}

@Composable
fun BuildingFacilityStatusView(building: CampusBuilding) {
    val dining = LocalApp.current.store.dining
    val restaurants = remember(building.id) { restaurants(building) }
    val venues = remember(building.id) { PlaceDirectory.venues(building) }
    val now = System.currentTimeMillis()
    Column(Modifier.fillMaxSize().background(BuildingDesign.canvas).verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        BuildingSurface {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                LabelText("실시간 정보 연결 전", Sym.people, Type.headline)
                Text("좌석 수나 혼잡도를 제공하는 데이터가 아직 없어요. 아래에는 공식 등록 운영시간을 안내해요.", style = Type.subheadline, color = Cj.secondary)
            }
        }
        restaurants.forEach { r ->
            BuildingSurface {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(r.name, style = Type.headline)
                    LabelText(dining.hours(r, now), Sym.clock, Type.subheadline, Cj.secondary)
                    Text("${dining.status(r, now).title} · 등록 시간 기준", style = Type.caption, color = BuildingDesign.green)
                }
            }
        }
        venues.forEach { venue ->
            BuildingSurface {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(venue.name, style = Type.headline)
                    Text("${venue.floor} · 평일 ${venue.weekdayHours}", style = Type.subheadline, color = Cj.secondary)
                    Text("좌석·혼잡 정보 확인 불가", style = Type.caption, color = Cj.secondary)
                }
            }
        }
        if (restaurants.isEmpty() && venues.isEmpty()) BuildingEmptyCard(Sym.clockQuestion, "운영시간 정보가 없어요", "건물 이용 안내의 운영기관 연락처를 확인해 주세요.")
    }
}

@Composable
fun BuildingIndoorView(building: CampusBuilding) {
    val nav = LocalNavigator.current
    var query by remember { mutableStateOf("") }
    val facilities = (building.details?.facilities ?: emptyList()).filter { PlaceDirectory.matches(query, listOf(it.name, it.category)) }
    val labs = PlaceDirectory.labs(building).filter { PlaceDirectory.matches(query, it.searchFields) }
    Column(Modifier.fillMaxSize().background(Cj.grouped)) {
        SearchField(query, { query = it }, "찾는 시설·연구실 검색", Modifier.padding(horizontal = 16.dp, vertical = 8.dp), background = Color.White, height = 38.dp)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            GroupSection(footer = "등록된 층과 호실로 공간을 찾아보세요. 실내 보행 경로와 출입구 위치는 운영기관에 확인해 주세요.")
            if (labs.isNotEmpty() || facilities.isNotEmpty()) GroupSection {
                labs.forEach { lab ->
                    GroupRow(onClick = { nav?.push("연구실") { ResearchLabView(lab) } }, chevron = true) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(lab.name, style = Type.headline)
                            Text(lab.room, style = Type.subheadline, color = Cj.secondary)
                        }
                    }
                }
                facilities.forEachIndexed { i, facility ->
                    GroupRow(showDivider = i != facilities.lastIndex) {
                        Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(facility.name, style = Type.headline)
                            LabelText(PlaceDirectory.floorName(facility.floor), Sym.layers, Type.subheadline, BuildingDesign.green)
                        }
                    }
                }
            }
            if (labs.isEmpty() && facilities.isEmpty()) ContentUnavailable("‘$query’에 대한 결과 없음", Sym.search, "검색어를 확인하거나 새로운 검색을 시도하세요.")
        }
    }
}

@Composable
fun CampusSpaceRecommendationsView(building: CampusBuilding) {
    val nav = LocalNavigator.current
    val planner = LocalApp.current.planner
    var kind by remember { mutableStateOf("전체") }
    val nextClass = CampusPlanning.nextClass(planner.data.classes)
    val spaces = remember(building.id, kind) {
        CampusSpace.all.filter { (kind == "전체" || it.kind == kind) && it.building.coordinate.distanceTo(building.coordinate) <= 700 }
            .sortedWith { a, b ->
                val da = a.building.coordinate.distanceTo(building.coordinate)
                val db = b.building.coordinate.distanceTo(building.coordinate)
                if (da == db) org.chargajoe.chajajwo.data.naturalOrder.compare(a.name, b.name) else da.compareTo(db)
            }
    }
    Column(Modifier.fillMaxSize().background(BuildingDesign.canvas).verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        BuildingSurface {
            Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                if (nextClass != null) {
                    val remaining = nextClass.startMinute - CampusPlanning.minuteOf(System.currentTimeMillis())
                    LabelText("다음 수업까지 ${remaining}분", Sym.calendarClock, Type.headline)
                    Text("${nextClass.title} · ${if (nextClass.buildingNumber.isEmpty()) "위치 미등록" else nextClass.buildingNumber + "동 " + nextClass.room}",
                        style = Type.subheadline, color = Cj.secondary)
                } else {
                    LabelText(if (planner.data.classes.isEmpty()) "시간표와 함께 공간을 찾아보세요" else "오늘 남은 수업이 없어요", Sym.sparkles, Type.headline)
                    Text("이 건물과 주변에 공식 등록된 공간을 모았어요.", style = Type.subheadline, color = Cj.secondary)
                }
            }
        }
        SegmentedPicker(listOf("전체", "카페", "도서·학습", "라운지"), kind, { it }) { kind = it }
        spaces.take(16).forEach { space ->
            BuildingSurface {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(Modifier.width(42.dp).height(52.dp), contentAlignment = Alignment.Center) {
                            SymbolIcon(if (space.kind == "카페") Sym.cupOutline else Sym.booksOutline, BuildingDesign.green, 26.dp)
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                            Text(space.name, style = Type.headline)
                            Text(space.locationLabel, style = Type.subheadline, color = Cj.secondary)
                            val distance = (space.building.coordinate.distanceTo(building.coordinate) / 10).roundToInt() * 10
                            Text(if (space.building.id == building.id) "이 건물 안" else "건물 간 직선거리 약 ${distance}m", style = Type.caption, color = Cj.secondary)
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.heightIn(min = 44.dp).tap {
                            nav?.push("할 일 추가") { CampusTaskEditorView(space.building, presetTitle = space.name + " 이용하기", presetLocation = space.locationLabel) }
                        }, contentAlignment = Alignment.CenterStart) { LabelText("할 일 추가", Sym.plus, Type.subheadline.w(FontWeight.SemiBold), Cj.tealText) }
                        Spacer(Modifier.weight(1f))
                        space.building.directionsURL?.let { url ->
                            DirectionsButton(url, space.name) { LabelText("길찾기", Sym.location, Type.subheadline.w(FontWeight.SemiBold), Cj.tealText, modifier = Modifier.heightIn(min = 44.dp)) }
                        }
                    }
                }
            }
        }
        if (spaces.isEmpty()) BuildingEmptyCard(Sym.search, "등록된 공간이 없어요", "다른 종류를 선택해 보세요.")
        Text("공식 등록 공간을 거리순으로 안내해요. 좌석·콘센트·정숙도는 확인되지 않았으며, 직선거리는 실제 보행거리와 달라요.", style = Type.caption, color = Cj.secondary)
        val destination = nextClass?.let { c -> CampusBuildingCatalog.all.firstOrNull { it.number == c.buildingNumber } }
        if (destination != null) {
            Box(Modifier.tap { nav?.push("건물 간 길찾기") { BuildingDirectionsScreen(building, destination) } }) {
                BuildingSurface { LabelText("이용 후 다음 수업으로 길찾기", Sym.walk, Type.headline, modifier = Modifier.heightIn(min = 44.dp)) }
            }
        }
    }
}

@Composable
fun CampusScheduleRouteView(building: CampusBuilding) {
    val nav = LocalNavigator.current
    val planner = LocalApp.current.planner
    val next = CampusPlanning.nextClass(planner.data.classes)
    val destination = next?.let { item -> CampusBuildingCatalog.all.firstOrNull { it.number == item.buildingNumber } }
    Column(Modifier.fillMaxSize().background(BuildingDesign.canvas).verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        BuildingSurface {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                LabelText("내 일정 기반 동선", Sym.calendar, Type.headline)
                LabelText(building.displayTitle, Sym.destinationPin, Type.headline, BuildingDesign.green)
                if (next != null) {
                    SymbolIcon(Sym.arrowDown, Cj.secondary, 18.dp)
                    Text("${next.title} · ${CampusPlanning.time(next.startMinute)} 시작", style = Type.headline)
                    Text(if (next.buildingNumber.isEmpty()) "수업 위치 미등록" else next.buildingNumber + "동 " + next.room, style = Type.subheadline, color = Cj.secondary)
                } else Text("오늘 남은 수업이 없거나 아직 시간표를 등록하지 않았어요.", style = Type.subheadline, color = Cj.secondary)
            }
        }
        MiniMap(building, destination, Modifier.fillMaxWidth().height(240.dp).clip(RoundedCornerShape(18.dp)))
        Text("등록된 건물 위치를 표시해요. 실제 보행 경로와 시간은 길찾기에서 확인해 주세요.", style = Type.caption, color = Cj.secondary)
        BuildingDirectionsBanner(building)
        if (destination != null) {
            Row(Modifier.fillMaxWidth().heightIn(min = 54.dp).background(BuildingDesign.green, CircleShape)
                .tap { nav?.push("건물 간 길찾기") { BuildingDirectionsScreen(building, destination) } },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                LabelText("다음 수업까지 길찾기", Sym.walk, Type.headline, Color.White)
            }
        } else {
            Text("시간표 등록·수정", style = Type.body, color = Cj.tealText,
                modifier = Modifier.heightIn(min = 44.dp).tap { nav?.push("내 시간표") { CampusTimetableView(building) } }.padding(vertical = 11.dp))
        }
    }
}

/** 선택한 건물(초록)과 다음 수업 건물(파랑)을 보여주는 작은 카카오 지도. */
@Composable
private fun MiniMap(building: CampusBuilding, destination: CampusBuilding?, modifier: Modifier) {
    val context = LocalContext.current
    val buildingPainter = androidx.compose.ui.graphics.vector.rememberVectorPainter(Sym.building)
    val bitmaps = remember { PinBitmaps(context, PinPainters(buildingPainter, emptyMap())) }
    val view = remember {
        MapView(context).apply {
            start(object : MapLifeCycleCallback() {
                override fun onMapDestroy() {}
                override fun onMapError(error: Exception) {}
            }, object : KakaoMapReadyCallback() {
                override fun onMapReady(kakaoMap: KakaoMap) {
                    val layer = kakaoMap.labelManager?.layer ?: return
                    fun add(b: CampusBuilding, color: Int) {
                        val image = bitmaps.dot(color)
                        layer.addLabel(LabelOptions.from(LatLng.from(b.latitude, b.longitude))
                            .setStyles(LabelStyles.from(LabelStyle.from(image.bitmap).setAnchorPoint(0.5f, 0.5f).setApplyDpScale(false))))
                    }
                    add(building, BuildingDesign.green.toArgb())
                    if (destination != null) {
                        add(destination, android.graphics.Color.rgb(0, 122, 255))
                        kakaoMap.moveCamera(CameraUpdateFactory.fitMapPoints(arrayOf(
                            LatLng.from(building.latitude, building.longitude), LatLng.from(destination.latitude, destination.longitude)), 120, 18))
                    }
                }
                override fun getPosition(): LatLng = LatLng.from(building.latitude, building.longitude)
                override fun getZoomLevel(): Int = 15
            })
        }
    }
    DisposableEffect(view) { view.resume(); onDispose { runCatching { view.finish() } } }
    AndroidView(factory = { view }, modifier = modifier)
}

