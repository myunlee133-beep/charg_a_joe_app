package org.chargajoe.chajajwo.ui.building

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.chargajoe.chajajwo.data.CampusAmenities
import org.chargajoe.chajajwo.data.CampusAmenity
import org.chargajoe.chajajwo.data.CampusAmenityKind
import org.chargajoe.chajajwo.data.CampusBuilding
import org.chargajoe.chajajwo.data.PlaceDirectory
import org.chargajoe.chajajwo.ui.AssetImage
import org.chargajoe.chajajwo.ui.BuildingDesign
import org.chargajoe.chajajwo.ui.BuildingEmptyCard
import org.chargajoe.chajajwo.ui.BuildingSurface
import org.chargajoe.chajajwo.ui.CapsuleChip
import org.chargajoe.chajajwo.ui.Cj
import org.chargajoe.chajajwo.ui.DirectionsButton
import org.chargajoe.chajajwo.ui.Disclosure
import org.chargajoe.chajajwo.ui.Divider
import org.chargajoe.chajajwo.ui.LabelText
import org.chargajoe.chajajwo.ui.LocalNavigator
import org.chargajoe.chajajwo.ui.PlaceSourceLink
import org.chargajoe.chajajwo.ui.Sym
import org.chargajoe.chajajwo.ui.SymbolIcon
import org.chargajoe.chajajwo.ui.TopicFlowLayout
import org.chargajoe.chajajwo.ui.Type
import org.chargajoe.chajajwo.ui.ink
import org.chargajoe.chajajwo.ui.tap
import org.chargajoe.chajajwo.ui.w
import org.chargajoe.chajajwo.ui.wash

@Composable
fun CampusAmenityIcon(kind: CampusAmenityKind, size: Dp = 42.dp) {
    Box(Modifier.size(size).background(kind.wash, RoundedCornerShape(size * 0.28f)), contentAlignment = Alignment.Center) {
        SymbolIcon(Sym.amenity(kind), kind.ink, size * 0.48f)
    }
}

@Composable
fun CampusAmenityRow(amenity: CampusAmenity, showBuilding: Boolean = false) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(12.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        CampusAmenityIcon(amenity.kind)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(amenity.name, style = Type.subheadline.w(FontWeight.SemiBold))
            Text(if (showBuilding) amenity.location else amenity.shortFloor + " · " + amenity.facility.category, style = Type.caption, color = Cj.secondary)
            amenity.weekdayHours?.let { Text("평일 $it", style = Type.caption, color = amenity.kind.ink) }
        }
        SymbolIcon(Sym.chevronRight, Cj.tertiary, 18.dp)
    }
}

@Composable
fun BuildingAmenityBadges(building: CampusBuilding, onSelect: (CampusAmenityKind) -> Unit) {
    val counts = remember(building.id) { CampusAmenityKind.highlights.map { it to CampusAmenities.inBuilding(building, it).size }.filter { it.second > 0 } }
    if (counts.isEmpty()) return
    TopicFlowLayout(8.dp) {
        counts.forEach { (kind, count) ->
            Row(Modifier.heightIn(min = 44.dp).background(kind.wash, CircleShape).tap { onSelect(kind) }.padding(horizontal = 11.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                SymbolIcon(Sym.amenity(kind), kind.ink, 14.dp)
                Text("${kind.title} $count", style = Type.caption.w(FontWeight.SemiBold), color = kind.ink)
            }
        }
    }
}

@Composable
fun BuildingAmenityDirectory(building: CampusBuilding, kind: CampusAmenityKind?, onKind: (CampusAmenityKind?) -> Unit) {
    val nav = LocalNavigator.current
    var floor by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(kind) { floor = null }
    val amenities = remember(building.id, kind) { CampusAmenities.inBuilding(building, kind) }
    val labs = remember(building.id, kind) { if (kind == null) PlaceDirectory.labs(building) else emptyList() }
    val floors = remember(amenities, labs) { (amenities.map { it.floor } + labs.map { it.floor }).toSet().sortedWith(PlaceDirectory.floorComparator) }

    Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text("층별로 둘러보기", style = Type.title3.w(FontWeight.Bold))
            Text("필요한 공간을 고르면 자세히 볼 수 있어요", style = Type.caption, color = Cj.secondary)
        }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CapsuleChip("전체", kind == null, BuildingDesign.green, unselectedColor = Color.White) { onKind(null); floor = null }
            CampusAmenityKind.highlights.forEach { item ->
                if (CampusAmenities.inBuilding(building, item).isNotEmpty()) {
                    CapsuleChip(item.title, kind == item, BuildingDesign.green, unselectedColor = Color.White) { onKind(item); floor = null }
                }
            }
        }
        if (floors.size > 1) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                FloorTab("전체 층", floor == null) { floor = null }
                floors.forEach { value -> FloorTab(value.replace("지상", ""), floor == value) { floor = value } }
            }
        }
        floors.filter { floor == null || floor == it }.forEach { level ->
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.width(42.dp).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(level.replace("지상", ""), style = Type.subheadline.w(FontWeight.Bold), color = BuildingDesign.green)
                    Box(Modifier.width(2.dp).weight(1f).background(BuildingDesign.line, CircleShape))
                }
                val shape = RoundedCornerShape(18.dp)
                Column(Modifier.weight(1f).background(Cj.surface, shape).border(1.dp, BuildingDesign.line.copy(alpha = 0.8f), shape)) {
                    val levelAmenities = amenities.filter { it.floor == level }
                    val levelLabs = labs.filter { it.floor == level }
                    levelAmenities.forEachIndexed { index, amenity ->
                        Box(Modifier.tap { nav?.push("시설 상세") { CampusAmenityDetailView(amenity) } }) { CampusAmenityRow(amenity) }
                        if (index != levelAmenities.lastIndex || levelLabs.isNotEmpty()) Divider(Modifier.padding(start = 66.dp))
                    }
                    levelLabs.forEach { lab ->
                        Row(Modifier.fillMaxWidth().tap { nav?.push("연구실") { ResearchLabView(lab) } }.padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Box(Modifier.width(42.dp), contentAlignment = Alignment.Center) { SymbolIcon(Sym.flask, BuildingDesign.green, 20.dp) }
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(lab.name, style = Type.subheadline.w(FontWeight.SemiBold))
                                Text("지도교수 ${lab.professor} · ${lab.field}", style = Type.caption, color = Cj.secondary)
                            }
                            SymbolIcon(Sym.chevronRight, Cj.tertiary, 16.dp)
                        }
                    }
                }
            }
        }
        if (floors.isEmpty()) BuildingEmptyCard(Sym.building, "등록된 시설이 없어요", "다른 종류를 선택해 보세요.")
        Text("공식 자료에 등록된 시설이에요. 상세 정보에서 운영시간·연락처와 자료 출처를 확인할 수 있어요.", style = Type.caption, color = Cj.secondary)
    }
}

@Composable
private fun FloorTab(title: String, on: Boolean, onClick: () -> Unit) {
    Text(title, style = Type.subheadline.w(if (on) FontWeight.Bold else FontWeight.Normal), color = if (on) BuildingDesign.green else Cj.secondary,
        modifier = Modifier.heightIn(min = 44.dp).tap(onClick = onClick).padding(vertical = 12.dp))
}

@Composable
fun CampusAmenityDetailView(amenity: CampusAmenity) {
    val nav = LocalNavigator.current
    val uri = LocalUriHandler.current
    Column(Modifier.fillMaxSize().background(BuildingDesign.canvas).verticalScroll(rememberScrollState()).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Column(Modifier.fillMaxWidth().background(Color.White, RoundedCornerShape(22.dp)).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                CampusAmenityIcon(amenity.kind, 62.dp)
                Spacer(Modifier.weight(1f))
                Text(amenity.facility.category, style = Type.caption.w(FontWeight.SemiBold), color = amenity.kind.ink,
                    modifier = Modifier.background(amenity.kind.wash, CircleShape).padding(horizontal = 12.dp, vertical = 8.dp))
            }
            Text(amenity.name, style = Type.title.w(FontWeight.Bold))
            LabelText(amenity.location, Sym.pinEllipse, Type.subheadline, Cj.secondary)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                amenity.building.directionsURL?.let { url ->
                    DirectionsButton(url, amenity.name, Modifier.weight(1f)) {
                        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).background(BuildingDesign.green, RoundedCornerShape(13.dp)).padding(horizontal = 12.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                            LabelText("건물까지 길찾기", Sym.locationFill, Type.subheadline.w(FontWeight.SemiBold), Color.White)
                        }
                    }
                }
                val phone = amenity.phone?.let { PlaceDirectory.phoneURL(it) }
                if (phone != null) {
                    Row(Modifier.widthIn(min = 76.dp).heightIn(min = 48.dp).background(BuildingDesign.mint, RoundedCornerShape(13.dp))
                        .tap { runCatching { uri.openUri(phone) } }.padding(horizontal = 12.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                        LabelText("전화", Sym.phoneFill, Type.subheadline.w(FontWeight.SemiBold), Cj.tealText)
                    }
                }
            }
            amenity.phone?.let { Text(it, style = Type.subheadline, color = Cj.secondary) }
        }
        BuildingSurface {
            Column(verticalArrangement = Arrangement.spacedBy(15.dp)) {
                LabelText("운영시간", Sym.clock, Type.headline)
                val weekday = amenity.weekdayHours
                if (weekday != null) {
                    HoursRow("평일", weekday)
                    amenity.info?.saturdayHours?.let { HoursRow("토요일", it) }
                    amenity.info?.holidayHours?.let { HoursRow("휴일", it) }
                    Text("공개된 운영시간 기준이에요. 학기·방학·임시휴무에 따라 달라질 수 있어요.", style = Type.caption, color = Cj.secondary)
                } else {
                    Text("운영시간이 아직 등록되지 않았어요.", style = Type.subheadline, color = Cj.secondary)
                    Text("방문 전 공식 안내나 운영기관에 확인해 주세요.", style = Type.caption, color = Cj.secondary)
                }
                amenity.info?.note?.let { Text(it, style = Type.caption, color = Cj.secondary) }
            }
        }
        amenity.venue?.let { venue ->
            Box(Modifier.tap { nav?.push("카페 메뉴") { CafeMenuView(venue) } }) {
                BuildingSurface {
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        val image = PlaceDirectory.imageName(venue.featuredMenu?.photoAsset ?: venue.photoAsset)
                        if (image != null) AssetImage(image, Modifier.width(92.dp).height(100.dp)) else CampusAmenityIcon(CampusAmenityKind.CAFE, 62.dp)
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("메뉴 둘러보기", style = Type.headline)
                            Text(venue.featuredMenu?.name ?: venue.photoCaption ?: "공식 안내에 수록된 메뉴", style = Type.subheadline, color = Cj.secondary)
                            Text("메뉴 사진·상세 보기  ›", style = Type.caption.w(FontWeight.SemiBold), color = BuildingDesign.green)
                        }
                    }
                }
            }
        }
        val info = amenity.info
        if (info != null && info.items.isNotEmpty()) {
            BuildingSurface {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text("이용할 수 있는 품목", style = Type.headline)
                    TopicFlowLayout(8.dp) {
                        info.items.forEach { item ->
                            Text(item, style = Type.subheadline, modifier = Modifier.background(amenity.kind.wash, CircleShape).padding(horizontal = 12.dp, vertical = 9.dp))
                        }
                    }
                }
            }
        }
        BuildingSurface {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                LabelText("건물 안 위치", Sym.layers, Type.headline)
                Text(amenity.building.name + " " + amenity.shortFloor, style = Type.title3.w(FontWeight.SemiBold))
                Text("지도와 길찾기는 건물 위치를 안내해요. 층과 출입구를 확인해 방문해 주세요.", style = Type.caption, color = Cj.secondary)
            }
        }
        Box(Modifier.padding(horizontal = 4.dp)) {
            Disclosure(label = { Text("자료 출처·확인일", style = Type.subheadline, modifier = Modifier.padding(vertical = 10.dp)) }) {
                Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    PlaceSourceLink("공식 시설 안내", amenity.sourceURL)
                    Text("자료 확인 · " + amenity.checkedAt, style = Type.caption, color = Cj.secondary)
                    Text("실시간 영업 상태·재고 정보는 제공하지 않아요.", style = Type.caption, color = Cj.secondary)
                }
            }
        }
    }
}

@Composable
private fun HoursRow(day: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(day, style = Type.subheadline, color = Cj.secondary, modifier = Modifier.width(50.dp))
        Text(value, style = Type.subheadline.w(FontWeight.Medium), modifier = Modifier.weight(1f))
    }
}
