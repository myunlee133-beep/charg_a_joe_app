package org.chargajoe.chajajwo.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import org.chargajoe.chajajwo.data.DiningData
import org.chargajoe.chajajwo.data.DiningMeal
import org.chargajoe.chajajwo.data.Place
import org.chargajoe.chajajwo.data.won

/** TimelineView(.periodic(by: 60)) */
@Composable
fun rememberMinuteClock(): Long {
    val now by produceState(System.currentTimeMillis()) {
        while (true) { delay(60_000 - System.currentTimeMillis() % 60_000); value = System.currentTimeMillis() }
    }
    return now
}

/** 식당 핀을 누르면 뜨는 날짜별 아침·점심·저녁 식단 시트. */
@Composable
fun SheetView(detent: SheetDetent, onDetent: (SheetDetent) -> Unit) {
    val store = LocalApp.current.store
    val place = Place.byID[store.sel] ?: Place.all.first()
    var menuDate by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(store.sel, store.open) { if (store.open) menuDate = System.currentTimeMillis() }
    val now = rememberMinuteClock()
    val dining = store.dining

    SwipeSheet(detent, onDetent, normalHeight = 400.dp, header = {
        Row(Modifier.padding(bottom = 14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            PlaceIcon(place.type)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(place.name, style = Type.title3.w(FontWeight.ExtraBold), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    val status = dining.status(place, now)
                    Badge(status.title, if (status.isOpen) Cj.teal else Cj.sub)
                }
                Row(Modifier.height(28.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(DiningData.dateTitle(menuDate), style = Type.subheadline.w(FontWeight.SemiBold))
                    Text("오늘", style = Type.caption2.w(FontWeight.Bold), color = Cj.orangeText,
                        modifier = Modifier.heightIn(min = 44.dp).tap { menuDate = System.currentTimeMillis() }.padding(vertical = 14.dp))
                }
            }
            Box(Modifier.size(32.dp).tap { store.closeSheet() }, contentAlignment = Alignment.Center) { SymbolIcon(Sym.xmark, Cj.sub, 18.dp) }
        }
    }) {
        Divider()
        Column(Modifier.weight(1f, fill = true)) {
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                val rowMin = maxOf(0.dp, (maxHeight - 2.dp) / 3)
                val hasCourt = dining.hasUnits(place, foodCourt = true)
                val hasMeals = dining.hasUnits(place, foodCourt = false) || !hasCourt
                Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 30.dp)) {
                    if (hasMeals) DiningMeal.entries.forEach { meal ->
                        MealRow(place, menuDate, meal, Modifier.heightIn(min = rowMin))
                        if (meal != DiningMeal.DINNER || hasCourt) Divider()
                    }
                    if (hasCourt) FoodCourtRow(place, menuDate)
                }
                DayButton(menuDate, -1, "전날", Sym.chevronLeft, Modifier.align(Alignment.CenterStart).offset(x = (-18).dp)) { menuDate = it }
                DayButton(menuDate, 1, "다음날", Sym.chevronRight, Modifier.align(Alignment.CenterEnd).offset(x = 18.dp)) { menuDate = it }
            }
            DirectionsButton(place.directionsURL, place.name, Modifier.padding(top = 12.dp)) { BigLabel("길찾기", BtnStyle.ORANGE_LINE) }
        }
    }
}

@Composable
private fun DayButton(date: Long, offset: Int, label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, modifier: Modifier, onChange: (Long) -> Unit) {
    val allowed = DiningData.canShow(date, offset)
    Box(modifier.size(44.dp).alpha(if (allowed) 1f else 0.25f).tap(allowed) { onChange(DiningData.addDays(date, offset)) }, contentAlignment = Alignment.Center) {
        SymbolIcon(icon, Cj.sub, 26.dp, contentDescription = "$label 식단")
    }
}

@Composable
private fun HoursTag(text: String) {
    Text(text, fontSize = 9.sp, fontWeight = FontWeight.Medium, fontFamily = FontFamily.Monospace, color = Cj.sub, lineHeight = 12.sp,
        modifier = Modifier.background(Cj.inset, RoundedCornerShape(5.dp)).padding(horizontal = 6.dp, vertical = 5.dp))
}

@Composable
private fun MealRow(place: Place, date: Long, meal: DiningMeal, modifier: Modifier) {
    val dining = LocalApp.current.store.dining
    val menus = dining.menus(place, date, meal)
    Row(modifier.fillMaxWidth().padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.width(84.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            LabelText(meal.title, Sym.meal(meal), Type.subheadline.w(FontWeight.SemiBold), Cj.orangeText)
            HoursTag(dining.hours(place, date, meal))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (menus.isEmpty()) Text("등록된 메뉴가 없어요", style = Type.subheadline, color = Cj.sub)
            else {
                val multiple = menus.map { it.unit }.toSet().size > 1
                menus.forEachIndexed { index, menu ->
                    if (multiple && (index == 0 || menus[index - 1].unit != menu.unit)) {
                        Text(menu.unit, style = Type.caption.w(FontWeight.Bold), color = Cj.sub, modifier = Modifier.padding(top = if (index == 0) 0.dp else 6.dp))
                    }
                    MenuLine(menu.name, menu.priceWon)
                }
            }
        }
    }
}

@Composable
private fun MenuLine(name: String, price: Int?) {
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(name, style = Type.subheadline, modifier = Modifier.weight(1f))
        if (price != null) Text("${price.won()}원", style = Type.caption, color = Cj.sub, modifier = Modifier.padding(top = 2.dp))
    }
}

@Composable
private fun FoodCourtRow(place: Place, date: Long) {
    val dining = LocalApp.current.store.dining
    val stalls = dining.foodCourtMenus(place, date)
    Row(Modifier.fillMaxWidth().padding(vertical = 14.dp), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.width(84.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            LabelText("푸드코트", Sym.forkKnife, Type.subheadline.w(FontWeight.SemiBold), Cj.orangeText)
            HoursTag(dining.foodCourtHours(place, date))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (stalls.isEmpty()) Text("등록된 메뉴가 없어요", style = Type.subheadline, color = Cj.sub)
            stalls.forEachIndexed { index, stall ->
                Text(stall.stall, style = Type.caption.w(FontWeight.Bold), color = Cj.sub, modifier = Modifier.padding(top = if (index == 0) 0.dp else 10.dp))
                stall.menus.forEach { MenuLine(it.name, it.priceWon) }
            }
        }
    }
}

/** 셔틀 정류장 카드. */
@Composable
fun HomePlaceCard(place: Place, detent: SheetDetent, onDetent: (SheetDetent) -> Unit) {
    val store = LocalApp.current.store
    SwipeSheet(detent, onDetent, header = {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PlaceIcon(place.type)
            Text(place.name, style = Type.headline, modifier = Modifier.weight(1f))
            Box(Modifier.size(36.dp).tap { store.closeSheet() }, contentAlignment = Alignment.Center) {
                SymbolIcon(Sym.xmarkCircle, Cj.sub, 22.dp, contentDescription = "장소 정보 닫기")
            }
        }
    }) {
        ShuttleStatusContent()
        DirectionsButton(place.directionsURL, place.name) {
            LabelText("길찾기", Sym.directions, Type.subheadline, Cj.tealText, modifier = Modifier.heightIn(min = 44.dp))
        }
    }
}

@Composable
fun ShuttleStatusContent() {
    val shuttle = LocalApp.current.shuttle
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(shuttle.status, style = Type.subheadline.w(FontWeight.SemiBold), color = Cj.blue)
        shuttle.queriedAt?.let {
            val c = org.chargajoe.chajajwo.data.seoulCalendar(it)
            val ampm = if (c.get(java.util.Calendar.AM_PM) == 0) "오전" else "오후"
            val h = c.get(java.util.Calendar.HOUR).let { h -> if (h == 0) 12 else h }
            Text("조회 $ampm $h:%02d:%02d".format(c.get(java.util.Calendar.MINUTE), c.get(java.util.Calendar.SECOND)), style = Type.caption, color = Cj.sub)
        }
        shuttle.statusPositions.take(3).forEach { bus ->
            LabelText("교내순환 · 다음 ${bus.nextStop}", Sym.bus, Type.subheadline)
        }
        Text("위치는 노선도 좌표를 도로 위에 보정한 추정치예요. 도착예정시간은 현재 데이터에서 제공하지 않아요.", style = Type.caption, color = Cj.sub)
        if (shuttle.heldCount > 0) Text("불확실한 위치 ${shuttle.heldCount}건 확인 중", style = Type.caption, color = Cj.sub)
    }
}

