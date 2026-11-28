package org.chargajoe.chajajwo.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.chargajoe.chajajwo.data.CampusBuilding
import org.chargajoe.chajajwo.data.CampusBuildingCatalog
import org.chargajoe.chajajwo.data.DirectionsTransport
import org.chargajoe.chajajwo.data.DirectionsURL

private enum class EndpointField(val title: String) { ORIGIN("출발 건물"), DESTINATION("도착 건물") }

/** 출발·도착 건물을 골라 앱 안에서 두 건물 사이 경로를 연다. */
@Composable
fun BuildingDirectionsScreen(initialOrigin: CampusBuilding? = null, initialDestination: CampusBuilding? = null, onClose: (() -> Unit)? = null) {
    var origin by remember { mutableStateOf(initialOrigin) }
    var destination by remember { mutableStateOf(initialDestination) }
    var transport by remember { mutableStateOf(DirectionsTransport.WALK) }
    var selecting by remember { mutableStateOf<EndpointField?>(null) }

    val routeURL = if (origin != null && destination != null && origin!!.id != destination!!.id)
        DirectionsURL.route(origin!!.directionsEndpoint, destination!!.directionsEndpoint, transport) else null
    val routeName = "${origin?.displayTitle ?: "출발 건물"} → ${destination?.displayTitle ?: "도착 건물"}"

    val field = selecting
    if (field != null) {
        DirectionsBuildingPicker(field.title, if (field == EndpointField.ORIGIN) origin?.id else destination?.id,
            onCancel = { selecting = null }) { building ->
            if (field == EndpointField.ORIGIN) origin = building else destination = building
            selecting = null
        }
        return
    }

    Column(Modifier.fillMaxSize().background(Cj.grouped)) {
        if (onClose != null) NavBar("건물 간 길찾기", actions = { TextButton("닫기", onClick = onClose) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            val footer = if (origin != null && destination != null && routeURL == null) "출발지와 도착지가 같아요. 서로 다른 위치의 건물을 선택해주세요."
                else "건물 이름이나 동 번호로 검색할 수 있어요."
            GroupSection(header = "어디에서 어디로 갈까요?") {
                EndpointRow(EndpointField.ORIGIN, origin) { selecting = EndpointField.ORIGIN }
                EndpointRow(EndpointField.DESTINATION, destination) { selecting = EndpointField.DESTINATION }
                val swapEnabled = origin != null || destination != null
                GroupRow(Modifier.alpha(if (swapEnabled) 1f else 0.4f), onClick = if (swapEnabled) ({ val o = origin; origin = destination; destination = o }) else null, showDivider = false) {
                    LabelText("출발·도착 바꾸기", Sym.swap, Type.body, Cj.tealText)
                }
            }
            Text(footer, style = Type.footnote, color = if (footer.startsWith("출발지와")) Cj.orangeText else Cj.secondary,
                modifier = Modifier.padding(start = 32.dp, end = 32.dp, top = 7.dp))
            GroupSection(header = "이동 수단") {
                Box(Modifier.padding(12.dp)) {
                    SegmentedPicker(DirectionsTransport.entries, transport, { it.title }) { transport = it }
                }
            }
        }
        Box(Modifier.fillMaxWidth().background(Cj.surface).padding(16.dp)) {
            DirectionsButton(routeURL, routeName) {
                Row(Modifier.fillMaxWidth().heightIn(min = 50.dp).background(Cj.teal, RoundedCornerShape(12.dp)),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                    SymbolIcon(Sym.directionsFill, Color.White, 20.dp); HSpacer(8.dp)
                    Text("경로 보기", style = Type.headline, color = Color.White)
                }
            }
        }
    }
}

@Composable
private fun EndpointRow(field: EndpointField, building: CampusBuilding?, onClick: () -> Unit) {
    GroupRow(onClick = onClick, chevron = true) {
        SymbolIcon(if (field == EndpointField.ORIGIN) Sym.originDot else Sym.destinationPin,
            if (field == EndpointField.ORIGIN) Cj.tealText else Cj.orangeText, 26.dp)
        HSpacer(12.dp)
        Column(Modifier.weight(1f).heightIn(min = 36.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(field.title, style = Type.caption, color = Cj.sub)
            Text(building?.displayTitle ?: "건물을 선택해주세요", style = Type.body.w(if (building == null) FontWeight.Normal else FontWeight.SemiBold),
                color = if (building == null) Cj.sub else Color.Black)
        }
    }
}

@Composable
private fun DirectionsBuildingPicker(title: String, selectedID: String?, onCancel: () -> Unit, onSelect: (CampusBuilding) -> Unit) {
    var query by remember { mutableStateOf("") }
    val buildings = remember(query) { if (query.isBlank()) CampusBuildingCatalog.sortedByTitle else CampusBuildingCatalog.search(query) }
    BackHandler(onBack = onCancel)
    Column(Modifier.fillMaxSize().background(Color.White)) {
        NavBar("$title 선택", actions = { TextButton("취소", onClick = onCancel) })
        SearchField(query, { query = it }, "건물 이름 또는 동 번호", Modifier.padding(horizontal = 16.dp, vertical = 8.dp), height = 38.dp)
        if (buildings.isEmpty()) {
            ContentUnavailable(
                if (CampusBuildingCatalog.all.isEmpty()) "건물 목록을 불러오지 못했어요" else "검색 결과가 없어요", Sym.building,
                if (CampusBuildingCatalog.all.isEmpty()) "앱을 다시 실행한 뒤 확인해주세요." else "다른 건물 이름이나 동 번호로 검색해주세요.",
            )
        }
        LazyColumn(Modifier.weight(1f)) {
            items(buildings, key = { it.id }) { building ->
                Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).tap { onSelect(building) }.padding(horizontal = 20.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(building.name, style = Type.body.w(FontWeight.SemiBold))
                        Text(building.buildingNumberLabel, style = Type.subheadline, color = Cj.sub)
                    }
                    if (building.id == selectedID) SymbolIcon(Sym.check, Cj.tealText, 20.dp)
                }
                Divider(Modifier.padding(start = 20.dp))
            }
        }
    }
}
