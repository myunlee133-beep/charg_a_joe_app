package org.chargajoe.chajajwo.ui

import android.content.Context
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
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.chargajoe.chajajwo.Store
import org.chargajoe.chajajwo.data.DiningData
import org.chargajoe.chajajwo.data.DiningMeal
import org.chargajoe.chajajwo.data.Place
import org.chargajoe.chajajwo.data.PlaceType
import org.chargajoe.chajajwo.data.naturalOrder
import org.chargajoe.chajajwo.data.won
import org.chargajoe.chajajwo.ui.building.CafeDirectoryView

/** 식당 모아보기: 날짜·끼니별 공개 메뉴를 비교하고 지도에서 다시 찾는다. */
@Composable
fun DiningScreen() {
    val navigator = remember { Navigator() }
    Column(Modifier.fillMaxSize().background(Cj.surface).windowInsetsPadding(WindowInsets.statusBars)) {
        NavStack(navigator, Modifier.fillMaxSize()) { DiningRoot(navigator) }
    }
}

private class FavoriteStore(context: Context) {
    private val prefs = context.getSharedPreferences("cj_dining", Context.MODE_PRIVATE)
    fun load(): Set<String> = (prefs.getString("cj_favorite_restaurants", "") ?: "").split("|").filter { it.isNotEmpty() }.toSet()
    fun save(ids: Set<String>) = prefs.edit().putString("cj_favorite_restaurants", ids.sorted().joinToString("|")).apply()
}

private data class DiningRow(val place: Place, val dishes: List<DiningData.Menu>)

@Composable
private fun DiningRoot(navigator: Navigator) {
    val store = LocalApp.current.store
    val context = LocalContext.current
    val favoriteStore = remember { FavoriteStore(context) }
    var date by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var meal by remember { mutableStateOf(DiningMeal.LUNCH) }
    var query by remember { mutableStateOf("") }
    var onlyOpen by remember { mutableStateOf(false) }
    var onlyFavorites by remember { mutableStateOf(false) }
    var priceLimit by remember { mutableIntStateOf(0) }
    var favorites by remember { mutableStateOf(favoriteStore.load()) }
    val isToday = DiningData.isToday(date)
    val now = rememberMinuteClock()
    LaunchedEffect(date) { if (!DiningData.isToday(date)) onlyOpen = false }

    val dining = store.dining
    val rows = run {
        val search = query.trim()
        Place.all.mapNotNull { place ->
            if (place.type != PlaceType.FOOD) return@mapNotNull null
            if (onlyFavorites && place.id !in favorites) return@mapNotNull null
            if (onlyOpen && !dining.status(place, now).isOpen) return@mapNotNull null
            val regular = dining.menus(place, date, meal)
            val stalls = dining.foodCourtMenus(place, date).flatMap { it.menus }
            val dishes = (regular + stalls).filter { priceLimit == 0 || (it.priceWon?.let { p -> p <= priceLimit } ?: false) }
            if (priceLimit > 0 && dishes.isEmpty()) return@mapNotNull null
            if (search.isNotEmpty() && !place.name.contains(search, ignoreCase = true) &&
                dishes.none { (it.name + it.unit).contains(search, ignoreCase = true) }) return@mapNotNull null
            DiningRow(place, dishes)
        }.sortedWith { lhs, rhs ->
            if (lhs.dishes.isEmpty() != rhs.dishes.isEmpty()) (if (lhs.dishes.isNotEmpty()) -1 else 1)
            else naturalOrder.compare(lhs.place.name, rhs.place.name)
        }
    }

    Column(Modifier.fillMaxSize()) {
        NavBar(
            title = "식당",
            leading = {
                Row(Modifier.heightIn(min = 44.dp).tap { store.tab = Store.Tab.HOME; store.homeFilter = Store.HomeFilter.ALL }.padding(horizontal = 8.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    SymbolIcon(Sym.chevronLeft, Cj.tealText, 26.dp)
                    Text("지도", style = Type.subheadline.w(FontWeight.SemiBold), color = Cj.tealText)
                }
            },
            actions = {
                TextButton("오늘", Cj.orangeText, Type.subheadline.w(FontWeight.SemiBold)) { date = System.currentTimeMillis() }
                Box(Modifier.size(40.dp).tap { navigator.push("교내 카페") { CafeDirectoryView() } }, contentAlignment = Alignment.Center) {
                    SymbolIcon(Sym.cupOutline, Cj.tealText, 22.dp, contentDescription = "카페")
                }
            },
        )
        // 조작부
        Column(Modifier.padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth().background(Cj.inset, RoundedCornerShape(12.dp)), verticalAlignment = Alignment.CenterVertically) {
                DateArrow(Sym.chevronLeft, "전날 식단") { date = DiningData.addDays(date, -1) }
                Text(DiningData.dateTitle(date), style = Type.headline, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                DateArrow(Sym.chevronRight, "다음날 식단") { date = DiningData.addDays(date, 1) }
            }
            Row(Modifier.fillMaxWidth()) {
                DiningMeal.entries.forEach { option ->
                    val on = meal == option
                    Column(
                        Modifier.weight(1f).background(if (on) Cj.orangeFill.copy(alpha = 0.5f) else Color.Transparent, RoundedCornerShape(12.dp))
                            .tap { meal = option }.padding(vertical = 10.dp),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        SymbolIcon(Sym.meal(option), if (on) Cj.orangeText else Cj.sub, 26.dp)
                        Text(option.title, style = Type.subheadline.w(FontWeight.SemiBold), color = if (on) Cj.orangeText else Cj.sub)
                    }
                }
            }
            SearchField(query, { query = it }, "식당이나 메뉴 검색")
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterButton("지금 운영 중", Sym.circleFill, onlyOpen, enabled = isToday) { onlyOpen = !onlyOpen }
                FilterButton("즐겨찾기", Sym.star, onlyFavorites) { onlyFavorites = !onlyFavorites }
                var menuOpen by remember { mutableStateOf(false) }
                Box {
                    Row(Modifier.height(36.dp).background(Cj.inset, CircleShape).tap { menuOpen = true }.padding(horizontal = 12.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        val color = if (priceLimit == 0) Color.Black else Cj.orangeText
                        SymbolIcon(Sym.chevronDown, color, 16.dp)
                        Text(if (priceLimit == 0) "가격" else "${priceLimit.won()}원 이하", style = Type.caption.w(FontWeight.Medium), color = color)
                    }
                    DropdownMenu(menuOpen, onDismissRequest = { menuOpen = false }) {
                        listOf(0 to "모든 가격", 6000 to "6,000원 이하", 8000 to "8,000원 이하").forEach { (value, label) ->
                            DropdownMenuItem(text = { Text(label) }, onClick = { priceLimit = value; menuOpen = false },
                                trailingIcon = if (priceLimit == value) ({ SymbolIcon(Sym.check, Cj.tealText, 18.dp) }) else null)
                        }
                    }
                }
            }
        }
        Divider()
        LazyColumn(
            Modifier.fillMaxWidth().weight(1f).background(Cj.grouped),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                Row(Modifier.fillMaxWidth().padding(top = 16.dp)) {
                    Text("서울대 관악캠퍼스", style = Type.caption, color = Cj.sub)
                    Spacer(Modifier.weight(1f))
                    Text("식당 ${rows.size}곳", style = Type.caption.w(FontWeight.SemiBold))
                }
            }
            if (rows.isEmpty()) item { ContentUnavailable("조건에 맞는 식당이 없어요", Sym.forkKnife, "검색어나 필터를 바꿔 보세요.") }
            items(rows, key = { it.place.id }) { row ->
                RestaurantCard(row.place, row.dishes, date, meal, isToday, now, row.place.id in favorites,
                    onFavorite = {
                        val updated = favorites.toMutableSet()
                        if (!updated.add(row.place.id)) updated.remove(row.place.id)
                        favorites = updated; favoriteStore.save(updated)
                    },
                    onMap = { store.tab = Store.Tab.HOME; store.homeFilter = Store.HomeFilter.ALL; store.filter = null; store.select(row.place.id) })
            }
        }
    }
}

@Composable
private fun DateArrow(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(44.dp).tap(onClick = onClick), contentAlignment = Alignment.Center) { SymbolIcon(icon, Color.Black, 24.dp, contentDescription = label) }
}

@Composable
private fun FilterButton(title: String, icon: ImageVector, selected: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    Row(
        Modifier.height(36.dp).alpha(if (enabled) 1f else 0.45f)
            .background(if (selected) Cj.orangeFill.copy(alpha = 0.5f) else Cj.inset, CircleShape)
            .tap(enabled, onClick).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        val color = if (selected) Cj.orangeText else Color.Black
        SymbolIcon(icon, color, if (icon == Sym.circleFill) 9.dp else 15.dp)
        Text(title, style = Type.caption.w(FontWeight.Medium), color = color)
    }
}

@Composable
private fun RestaurantCard(
    place: Place, dishes: List<DiningData.Menu>, date: Long, meal: DiningMeal, isToday: Boolean, now: Long, favorite: Boolean,
    onFavorite: () -> Unit, onMap: () -> Unit,
) {
    val dining = LocalApp.current.store.dining
    val shape = RoundedCornerShape(18.dp)
    Column(Modifier.fillMaxWidth().background(Cj.surface, shape).border(1.dp, Cj.line.copy(alpha = 0.25f), shape).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text(place.name, style = Type.title3.w(FontWeight.Bold))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (isToday) {
                        val status = dining.status(place, now)
                        Badge(status.title, if (status.isOpen) Cj.tealText else Cj.sub)
                    }
                    Text(place.building, style = Type.caption, color = Cj.sub)
                }
            }
            Box(Modifier.size(44.dp).tap(onClick = onFavorite), contentAlignment = Alignment.Center) {
                SymbolIcon(if (favorite) Sym.starFill else Sym.star, Cj.orangeText, 24.dp,
                    contentDescription = place.name + if (favorite) " 즐겨찾기 해제" else " 즐겨찾기 추가")
            }
            Box(Modifier.size(44.dp).tap(onClick = onMap), contentAlignment = Alignment.Center) {
                SymbolIcon(Sym.map, Cj.tealText, 22.dp, contentDescription = place.name + " 지도에서 보기")
            }
        }
        LabelText(dining.hours(place, date).replace("-", "–"), Sym.clock, Type.caption, Cj.sub)
        Box(Modifier.fillMaxWidth().height(1.dp).background(Cj.orange.copy(alpha = 0.7f)))
        if (dishes.isEmpty()) {
            Text("이 날짜에 등록된 ${meal.title} 메뉴가 없어요", style = Type.subheadline, color = Cj.sub, modifier = Modifier.padding(vertical = 12.dp))
        } else {
            dishes.forEachIndexed { index, dish ->
                if (index == 0 || dishes[index - 1].unit != dish.unit) {
                    Text(DiningData.stallName(dish.unit) + if (DiningData.isFoodCourt(dish.unit)) " · 상시 메뉴" else "",
                        style = Type.caption.w(FontWeight.SemiBold), color = Cj.sub, modifier = Modifier.padding(top = if (index == 0) 0.dp else 8.dp))
                }
                Row(Modifier.padding(vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(dish.name, style = Type.subheadline, modifier = Modifier.weight(1f))
                    Text(dish.priceWon?.let { "${it.won()}원" } ?: "가격 미공개", style = Type.subheadline, color = Cj.sub)
                }
            }
        }
    }
}
