package org.chargajoe.chajajwo.ui.building

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.SubcomposeAsyncImage
import org.chargajoe.chajajwo.data.CampusAmenities
import org.chargajoe.chajajwo.data.CampusAmenity
import org.chargajoe.chajajwo.data.CampusAmenityKind
import org.chargajoe.chajajwo.data.CampusBuilding
import org.chargajoe.chajajwo.data.CampusBuildingPhoto
import org.chargajoe.chajajwo.data.Place
import org.chargajoe.chajajwo.ui.AssetImage
import org.chargajoe.chajajwo.ui.BuildingDesign
import org.chargajoe.chajajwo.ui.BuildingSurface
import org.chargajoe.chajajwo.ui.Cj
import org.chargajoe.chajajwo.ui.DirectionsButton
import org.chargajoe.chajajwo.ui.LabelText
import org.chargajoe.chajajwo.ui.LocalApp
import org.chargajoe.chajajwo.ui.LocalNavigator
import org.chargajoe.chajajwo.ui.NavStack
import org.chargajoe.chajajwo.ui.Navigator
import org.chargajoe.chajajwo.ui.PlaceSourceLink
import org.chargajoe.chajajwo.ui.Sym
import org.chargajoe.chajajwo.ui.SymbolIcon
import org.chargajoe.chajajwo.ui.Type
import org.chargajoe.chajajwo.ui.tap
import org.chargajoe.chajajwo.ui.w

/** 건물 상세 시트. iOS sheet(detents 0.68/large) + NavigationStack 대응. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BuildingExplorerSheet(
    building: CampusBuilding,
    onRestaurant: (Place) -> Unit,
    onDirections: () -> Unit,
    showTasksOnOpen: Boolean,
    initialKind: CampusAmenityKind?,
    initialAmenity: CampusAmenity?,
    onDismiss: () -> Unit,
) {
    val planner = LocalApp.current.planner
    val navigator = remember(building.id) { Navigator() }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = initialAmenity != null || initialKind != null)
    LaunchedEffect(building.id) {
        if (initialAmenity != null) navigator.push("시설 상세") { CampusAmenityDetailView(initialAmenity) }
        if (showTasksOnOpen) navigator.push("할 일 & 알림") { CampusTaskListView(building) }
    }
    LaunchedEffect(showTasksOnOpen) {
        if (showTasksOnOpen && navigator.stack.none { it.title == "할 일 & 알림" }) navigator.push("할 일 & 알림") { CampusTaskListView(building) }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor = Color.White,
        dragHandle = { Box(Modifier.padding(top = 8.dp, bottom = 4.dp).width(36.dp).height(5.dp).background(Cj.handle, CircleShape)) },
    ) {
        androidx.compose.runtime.CompositionLocalProvider(org.chargajoe.chajajwo.ui.LocalOverlayHost provides null) {
        Box(Modifier.fillMaxWidth().fillMaxHeight(0.94f)) {
            NavStack(navigator, Modifier.fillMaxSize()) {
                Column(Modifier.fillMaxSize()) {
                    Row(Modifier.fillMaxWidth().height(44.dp).padding(end = 8.dp), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(44.dp).tap(onClick = onDismiss), contentAlignment = Alignment.Center) {
                            SymbolIcon(Sym.xmark, BuildingDesign.green, 20.dp, contentDescription = "건물 정보 닫기")
                        }
                    }
                    BuildingOverviewView(building, onRestaurant, onDirections, initialKind)
                }
            }
        }
        }
    }

    planner.message?.let { message ->
        AlertDialog(
            onDismissRequest = { planner.message = null },
            title = { Text("방문 알림") },
            text = { Text(message) },
            confirmButton = { androidx.compose.material3.TextButton(onClick = { planner.message = null }) { Text("확인") } },
        )
    }
}

private enum class BuildingHubTab(val title: String) { HOME("홈"), FACILITIES("시설정보"), FOOD("식당·카페"), GUIDE("이용안내") }

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun BuildingOverviewView(building: CampusBuilding, onRestaurant: (Place) -> Unit, onDirections: () -> Unit, initialKind: CampusAmenityKind? = null) {
    val planner = LocalApp.current.planner
    var tab by remember { mutableStateOf(if (initialKind == null) BuildingHubTab.HOME else BuildingHubTab.FACILITIES) }
    var amenityKind by remember { mutableStateOf(initialKind) }
    val favorite = building.id in planner.data.favoriteBuildings

    LazyColumn(Modifier.fillMaxSize().background(BuildingDesign.canvas)) {
        item {
            Column(Modifier.fillMaxWidth().background(Color.White).padding(horizontal = 18.dp).padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(15.dp)) {
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(building.name, style = Type.title2.w(FontWeight.Bold))
                        Text(building.buildingNumberLabel + " · " + (building.details?.category ?: "캠퍼스 공간"), style = Type.subheadline, color = Cj.secondary)
                        building.details?.englishName?.let { Text(it, style = Type.caption, color = Cj.secondary) }
                    }
                    Box(Modifier.size(44.dp).background(BuildingDesign.mint, CircleShape).tap { planner.toggleFavorite(building) }, contentAlignment = Alignment.Center) {
                        SymbolIcon(if (favorite) Sym.starFill else Sym.star, BuildingDesign.green, 22.dp,
                            contentDescription = if (favorite) "즐겨찾기 해제" else "즐겨찾기 추가")
                    }
                }
                BuildingHeroPhoto(building, if (tab == BuildingHubTab.FACILITIES) 120.dp else 168.dp)
                BuildingDirectionsBanner(building)
            }
        }
        stickyHeader {
            Box(Modifier.fillMaxWidth().background(Color.White)) {
                Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 15.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    BuildingHubTab.entries.forEach { option ->
                        val on = tab == option
                        Column(Modifier.widthIn(min = 82.dp).tap { tab = option }.padding(top = 15.dp, start = 3.dp, end = 3.dp),
                            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(13.dp)) {
                            Text(option.title, style = Type.subheadline.w(if (on) FontWeight.Bold else FontWeight.Medium), color = if (on) BuildingDesign.green else Cj.secondary)
                            Box(Modifier.fillMaxWidth().height(3.dp).background(if (on) BuildingDesign.green else Color.Transparent, CircleShape))
                        }
                    }
                }
                Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(1.dp).background(BuildingDesign.line))
            }
        }
        item {
            Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                when (tab) {
                    BuildingHubTab.HOME -> BuildingHomeTab(building, onKind = { amenityKind = it; tab = BuildingHubTab.FACILITIES })
                    BuildingHubTab.FACILITIES -> BuildingFacilityTab(building, amenityKind) { amenityKind = it }
                    BuildingHubTab.FOOD -> BuildingFoodCards(building, onRestaurant)
                    BuildingHubTab.GUIDE -> BuildingGuideTab(building, onDirections)
                }
            }
        }
    }
}

@Composable
private fun BuildingHomeTab(building: CampusBuilding, onKind: (CampusAmenityKind?) -> Unit) {
    val nav = LocalNavigator.current
    val planner = LocalApp.current.planner
    val amenityCount = remember(building.id) { CampusAmenities.inBuilding(building).size }
    if (amenityCount > 0) {
        BuildingSurface {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("이 건물에서 찾을 수 있어요", style = Type.headline)
                BuildingAmenityBadges(building) { onKind(it) }
                Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).tap { onKind(null) }, verticalAlignment = Alignment.CenterVertically) {
                    Text("층별 시설 ${amenityCount}곳 모두 보기", style = Type.subheadline.w(FontWeight.SemiBold), color = Cj.tealText, modifier = Modifier.weight(1f))
                    SymbolIcon(Sym.arrowRight, Cj.tealText, 18.dp)
                }
            }
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Feature("할 일 & 알림", "일정 관리, 방문 알림", Sym.checklist, Modifier.weight(1f)) { nav?.push("할 일 & 알림") { CampusTaskListView(building) } }
            Feature("공강 공간 추천", "내 일정에 맞는 공간", Sym.sparkles, Modifier.weight(1f)) { nav?.push("공강 공간 추천") { CampusSpaceRecommendationsView(building) } }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Feature("내부 공간 찾기", "층과 호실 안내", Sym.pinEllipse, Modifier.weight(1f)) { nav?.push("내부 공간 찾기") { BuildingIndoorView(building) } }
            Feature("시설 현황", "운영시간 · 정보 확인", Sym.chart, Modifier.weight(1f)) { nav?.push("시설 현황") { BuildingFacilityStatusView(building) } }
        }
    }
    UpcomingTasks(building)
    Box(Modifier.tap { nav?.push("내 시간표") { CampusTimetableView(building) } }) {
        BuildingSurface {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SymbolIcon(Sym.calendar, BuildingDesign.green, 26.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text("내 시간표", style = Type.headline)
                    Text(if (planner.data.classes.isEmpty()) "수업을 등록하고 방문 시간을 찾아보세요"
                        else "등록한 수업 ${planner.data.classes.size}개 · 방문 추천 시간 보기", style = Type.caption, color = Cj.secondary)
                }
                SymbolIcon(Sym.chevronRight, Cj.secondary, 16.dp)
            }
        }
    }
}

@Composable
private fun Feature(title: String, subtitle: String, icon: androidx.compose.ui.graphics.vector.ImageVector, modifier: Modifier, onClick: () -> Unit) {
    Box(modifier.tap(onClick = onClick)) {
        BuildingSurface(padding = 14.dp) {
            Row(Modifier.heightIn(min = 63.dp), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SymbolIcon(icon, BuildingDesign.green, 25.dp)
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(title, style = Type.subheadline.w(FontWeight.Bold))
                    Text(subtitle, style = Type.caption, color = Cj.secondary)
                }
            }
        }
    }
}

@Composable
private fun UpcomingTasks(building: CampusBuilding) {
    val nav = LocalNavigator.current
    val planner = LocalApp.current.planner
    BuildingSurface {
        Column(verticalArrangement = Arrangement.spacedBy(13.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                LabelText("다가오는 할 일", Sym.bell, Type.headline, modifier = Modifier.weight(1f))
                Text("전체 보기", style = Type.caption, color = Cj.tealText, modifier = Modifier.tap { nav?.push("할 일 & 알림") { CampusTaskListView(building) } }.padding(8.dp))
            }
            val tasks = planner.tasks(building).take(2)
            if (tasks.isEmpty()) {
                Text("이 건물에서 할 일을 기록해 두세요.", style = Type.subheadline, color = Cj.secondary)
                Box(Modifier.heightIn(min = 44.dp).tap { nav?.push("할 일 추가") { CampusTaskEditorView(building) } }, contentAlignment = Alignment.CenterStart) {
                    LabelText("할 일 추가", Sym.plus, Type.subheadline.w(FontWeight.SemiBold), Cj.tealText)
                }
            } else tasks.forEach { CampusTaskRow(it) }
        }
    }
}

@Composable
private fun BuildingGuideTab(building: CampusBuilding, onDirections: () -> Unit) {
    val nav = LocalNavigator.current
    Box(Modifier.tap { nav?.push("이용 안내") { BuildingGuideView(building, onDirections) } }) {
        BuildingSurface {
            Column(verticalArrangement = Arrangement.spacedBy(15.dp)) {
                Text("건물 이용 정보", style = Type.headline)
                LabelText(building.details?.phone ?: "대표전화 미등록", Sym.phone, Type.subheadline, Cj.secondary)
                LabelText("운영기관 홈페이지·접근성·공식 안내", Sym.info, Type.subheadline, Cj.secondary)
                Text("이용 안내 자세히 보기  ›", style = Type.subheadline.w(FontWeight.SemiBold), color = Cj.tealText)
            }
        }
    }
    Box(Modifier.tap { nav?.push("내 시간표") { CampusTimetableView(building, initialRecommendations = true) } }) {
        BuildingSurface { LabelText("내 시간표로 방문 시간 찾기", Sym.calendarClock, Type.headline, modifier = Modifier.heightIn(min = 44.dp)) }
    }
    Box(Modifier.tap { nav?.push("일정 연동 길찾기") { CampusScheduleRouteView(building) } }) {
        BuildingSurface { LabelText("내 일정과 건물 간 동선 확인", Sym.route, Type.headline, modifier = Modifier.heightIn(min = 44.dp)) }
    }
    CampusBuildingPhoto.photo(building)?.let { photo ->
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            PlaceSourceLink(photo.credit, photo.photoURL)
            Text("사진 자료 확인 · ${photo.checkedAt}", style = Type.caption, color = Cj.secondary)
        }
    }
}

@Composable
fun BuildingFacilityTab(building: CampusBuilding, kind: CampusAmenityKind?, onKind: (CampusAmenityKind?) -> Unit) {
    val nav = LocalNavigator.current
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(Modifier.fillMaxWidth().heightIn(min = 48.dp).background(Color.White, RoundedCornerShape(12.dp))
            .tap { nav?.push("층별 공간") { BuildingFloorView(building) } }.padding(horizontal = 14.dp), contentAlignment = Alignment.CenterStart) {
            LabelText("연구실·지도교수·시설 검색", Sym.search, Type.subheadline, Cj.secondary)
        }
        BuildingAmenityDirectory(building, kind, onKind)
    }
}

@Composable
fun BuildingHeroPhoto(building: CampusBuilding, height: Dp = 168.dp) {
    val photo = remember(building.id) { CampusBuildingPhoto.photo(building) }
    val shape = RoundedCornerShape(20.dp)
    Box(Modifier.fillMaxWidth().height(height).clip(shape)) {
        val placeholder: @Composable () -> Unit = {
            Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(BuildingDesign.mint, Color.White))), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SymbolIcon(Sym.buildingOutline, BuildingDesign.green.copy(alpha = 0.7f), 40.dp)
                    Text("건물 사진 준비 중", style = Type.caption, color = Cj.secondary)
                }
            }
        }
        when {
            photo?.assetName != null && org.chargajoe.chajajwo.data.PlaceResources.drawableId(photo.assetName) != null ->
                AssetImage(photo.assetName, Modifier.fillMaxSize(), ContentScale.Crop, building.name + " 공식 건물 사진")
            photo?.remoteURL != null -> SubcomposeAsyncImage(
                model = photo.remoteURL, contentDescription = building.name + " 공식 건물 사진", contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(), loading = { placeholder() }, error = { placeholder() },
            )
            else -> placeholder()
        }
        if (photo != null) {
            Text("공식 건물 사진", style = Type.caption2.w(FontWeight.Medium), color = Color.White,
                modifier = Modifier.align(Alignment.BottomEnd).padding(10.dp).background(Color.Black.copy(alpha = 0.5f), CircleShape).padding(horizontal = 10.dp, vertical = 6.dp))
        }
    }
}

@Composable
fun BuildingDirectionsBanner(building: CampusBuilding) {
    val url = building.directionsURL ?: return
    DirectionsButton(url, building.name) {
        Row(Modifier.fillMaxWidth().heightIn(min = 58.dp)
            .background(Brush.horizontalGradient(listOf(BuildingDesign.mint, org.chargajoe.chajajwo.ui.hex(0xc8eade))), RoundedCornerShape(18.dp))
            .padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SymbolIcon(Sym.location, BuildingDesign.green, 24.dp)
            Text("길찾기", style = Type.headline, color = BuildingDesign.green)
            SymbolIcon(Sym.chevronRight, BuildingDesign.green, 18.dp)
            Spacer(Modifier.weight(1f))
            SymbolIcon(Sym.route, BuildingDesign.green.copy(alpha = 0.3f), 38.dp)
        }
    }
}
