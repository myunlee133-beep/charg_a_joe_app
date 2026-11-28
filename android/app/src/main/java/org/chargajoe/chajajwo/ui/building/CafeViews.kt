package org.chargajoe.chajajwo.ui.building

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.chargajoe.chajajwo.data.CampusVenue
import org.chargajoe.chajajwo.data.PlaceDirectory
import org.chargajoe.chajajwo.data.VenueMenu
import org.chargajoe.chajajwo.ui.AssetImage
import org.chargajoe.chajajwo.ui.Cj
import org.chargajoe.chajajwo.ui.ContentUnavailable
import org.chargajoe.chajajwo.ui.Disclosure
import org.chargajoe.chajajwo.ui.Divider
import org.chargajoe.chajajwo.ui.LabelText
import org.chargajoe.chajajwo.ui.LinkText
import org.chargajoe.chajajwo.ui.LocalNavigator
import org.chargajoe.chajajwo.ui.PlaceSourceLink
import org.chargajoe.chajajwo.ui.SearchField
import org.chargajoe.chajajwo.ui.Sym
import org.chargajoe.chajajwo.ui.SymbolIcon
import org.chargajoe.chajajwo.ui.Type
import org.chargajoe.chajajwo.ui.hex
import org.chargajoe.chajajwo.ui.tap
import org.chargajoe.chajajwo.ui.w

@Composable
fun CafeDirectoryView() {
    val nav = LocalNavigator.current
    var query by remember { mutableStateOf("") }
    val venues = PlaceDirectory.venues.filter { PlaceDirectory.matches(query, it.searchFields) }
    Column(Modifier.fillMaxSize().background(Cj.grouped)) {
        SearchField(query, { query = it }, "카페·동 번호·메뉴 검색", Modifier.padding(horizontal = 16.dp, vertical = 8.dp), background = Color.White, height = 38.dp)
        LazyColumn(Modifier.weight(1f).padding(horizontal = 16.dp)) {
            item { Spacer(Modifier.height(10.dp)) }
            if (venues.isNotEmpty()) item {
                Column(Modifier.fillMaxWidth().background(Color.White, RoundedCornerShape(10.dp))) {
                    venues.forEachIndexed { i, venue ->
                        Box(Modifier.tap { nav?.push("카페 메뉴") { CafeMenuView(venue) } }.padding(horizontal = 16.dp)) { CafeDirectoryRow(venue) }
                        if (i != venues.lastIndex) Divider(Modifier.padding(start = 16.dp))
                    }
                }
            }
            item {
                Text("공식 자료로 확인한 카페 ${PlaceDirectory.venues.size}곳을 안내해요. 매장별 메뉴 정보와 사진의 등록 범위가 달라요.",
                    style = Type.footnote, color = Cj.secondary, modifier = Modifier.padding(16.dp))
            }
            if (venues.isEmpty()) item { ContentUnavailable("‘$query’에 대한 결과 없음", Sym.search, "검색어를 확인하거나 새로운 검색을 시도하세요.") }
        }
    }
}

@Composable
private fun CafeDirectoryRow(venue: CampusVenue) {
    val photo = venue.featuredMenu?.photoAsset ?: venue.menus.firstOrNull { it.photoAsset != null }?.photoAsset ?: venue.photoAsset
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        val name = PlaceDirectory.imageName(photo)
        if (name != null) AssetImage(name, Modifier.width(72.dp).height(80.dp).background(hex(0xF2F2F7), RoundedCornerShape(12.dp)))
        else Box(Modifier.width(72.dp).height(80.dp).background(hex(0x767680).copy(alpha = 0.12f), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
            SymbolIcon(Sym.cupOutline, Cj.secondary, 26.dp)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(venue.name, style = Type.headline)
            Text("${venue.buildingNumber}동 · ${venue.floor}", style = Type.caption, color = Cj.secondary)
            venue.featuredMenu?.let { Text(it.name, style = Type.caption, color = Cj.tealText) }
        }
        SymbolIcon(Sym.chevronRight, Cj.tertiary, 18.dp)
    }
}

@Composable
fun CafeMenuView(venue: CampusVenue) {
    val nav = LocalNavigator.current
    Column(Modifier.fillMaxSize().background(Cj.grouped).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(26.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("${venue.buildingNumber}동 · ${venue.floor}", style = Type.subheadline, color = Cj.secondary)
            Text(venue.name, style = Type.largeTitle)
        }
        val featured = venue.featuredMenu
        if (featured != null) {
            Column(Modifier.fillMaxWidth().background(Color.White, RoundedCornerShape(20.dp)).tap { nav?.push("메뉴 상세") { CafeMenuDetailView(venue, featured) } },
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                MenuPhoto(featured.photoAsset, featured.name, 210.dp)
                Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("시그니처 메뉴", style = Type.caption.w(FontWeight.SemiBold), color = Cj.tealText)
                    Text(featured.name, style = Type.title3.w(FontWeight.Bold))
                    Text("메뉴 자세히 보기", style = Type.caption, color = Cj.secondary)
                }
            }
        } else if (venue.photoAsset != null) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MenuPhoto(venue.photoAsset, venue.photoCaption ?: venue.name, 210.dp)
                Text(venue.photoCaption ?: "카페 메뉴 사진", style = Type.caption, color = Cj.secondary)
                venue.photoCredit?.let { Text(it, style = Type.caption2, color = Cj.secondary) }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("메뉴 둘러보기", style = Type.title3.w(FontWeight.Bold))
            venue.menus.chunked(2).forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    pair.forEach { menu ->
                        Column(Modifier.weight(1f).tap { nav?.push("메뉴 상세") { CafeMenuDetailView(venue, menu) } }, verticalArrangement = Arrangement.spacedBy(9.dp)) {
                            if (menu.photoAsset != null) MenuPhoto(menu.photoAsset, menu.name, 145.dp)
                            Text(menu.name, style = Type.subheadline.w(FontWeight.SemiBold))
                            Text(menu.priceLabel, style = Type.caption, color = Cj.secondary)
                        }
                    }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
        Text(venue.menuNote, style = Type.footnote, color = Cj.secondary)
        Disclosure(label = { Text("운영시간·문의·출처", style = Type.subheadline.w(FontWeight.SemiBold), color = Cj.tealText, modifier = Modifier.padding(vertical = 10.dp)) }) {
            Column(Modifier.padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                LabelText("평일 ${venue.weekdayHours}", Sym.clock, Type.body)
                Text("방학·휴일 운영은 매장에 확인해 주세요.", style = Type.caption, color = Cj.secondary)
                PlaceDirectory.phoneURL(venue.phone)?.let { LinkText(venue.phone, it) }
                PlaceSourceLink("매장 공식 안내", venue.sourceURL)
                PlaceSourceLink("공식 메뉴 원문", venue.menuSourceURL)
                venue.featuredMenu?.photoCredit?.let { Text(it, style = Type.caption, color = Cj.secondary) }
                Text("공식 자료 확인 · ${venue.checkedAt}", style = Type.caption, color = Cj.secondary)
            }
        }
    }
}

@Composable
private fun MenuPhoto(asset: String?, label: String, height: Dp) {
    val name = PlaceDirectory.imageName(asset) ?: return
    AssetImage(name, Modifier.fillMaxWidth().height(height).background(Color.White, RoundedCornerShape(16.dp)), contentDescription = "$label 공식 메뉴 사진")
}

@Composable
fun CafeMenuDetailView(venue: CampusVenue, menu: VenueMenu) {
    Column(Modifier.fillMaxSize().background(Color.White).verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        if (menu.photoAsset != null) MenuPhoto(menu.photoAsset, menu.name, 300.dp)
        Text(menu.name, style = Type.largeTitle)
        Text(menu.priceLabel, style = Type.headline, color = Cj.secondary)
        Text(menu.description, style = Type.body)
        Text(venue.menuNote, style = Type.footnote, color = Cj.secondary)
        Divider()
        PlaceSourceLink("공식 메뉴 원문", venue.menuSourceURL)
        menu.photoSourceURL?.let { PlaceSourceLink(menu.photoCredit ?: "공식 메뉴 사진 출처", it) }
        Text("공식 자료 확인 · ${venue.checkedAt}", style = Type.caption, color = Cj.secondary)
    }
}
