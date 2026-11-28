package org.chargajoe.chajajwo.ui.treasure

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.PinDrop
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.chargajoe.chajajwo.LandmarkCollection
import org.chargajoe.chajajwo.data.CampusCoordinate
import org.chargajoe.chajajwo.data.Landmark
import org.chargajoe.chajajwo.data.TreasureGrade
import org.chargajoe.chajajwo.ui.AssetImage
import org.chargajoe.chajajwo.ui.FullScreenDialog
import org.chargajoe.chajajwo.ui.SymbolIcon
import org.chargajoe.chajajwo.ui.hex
import org.chargajoe.chajajwo.ui.tap
import java.util.Locale

val TreasureGrade.color: Color
    get() = when (this) {
        TreasureGrade.COMMON -> hex(0x7c838c)
        TreasureGrade.RARE -> hex(0x2f6fe4)
        TreasureGrade.LEGENDARY -> hex(0xb8860b)
    }

/** 보물 일러스트. 미발견이면 회색 실루엣 + "?". */
@Composable
fun TreasureIcon(treasure: Landmark, modifier: Modifier = Modifier, locked: Boolean = false) {
    BoxWithConstraints(modifier, contentAlignment = Alignment.Center) {
        AssetImage(if (locked) "${treasure.art}-locked" else treasure.art, Modifier.fillMaxSize())
        if (locked) {
            val side = minOf(maxWidth, maxHeight)
            Text("?", fontSize = (side.value * 0.32f).sp, fontWeight = FontWeight.Black, color = Color.White)
        }
    }
}

private val DexGreen = hex(0x1f6b3d)
private val DexInk = hex(0x1d2229)
private val DexGray = hex(0x6f7680)
private val DexPage = hex(0xf2f5f7)

/** 보물 도감: 발견한 보물은 일러스트, 미발견은 실루엣·단서. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LandmarkDexView(collection: LandmarkCollection, here: CampusCoordinate?, onDismiss: () -> Unit, onTestAR: (Landmark) -> Unit) {
    var filter by remember { mutableStateOf<TreasureGrade?>(null) }
    var selected by remember { mutableStateOf<Landmark?>(null) }
    val ids = collection.ids
    val shown = Landmark.all.filter { filter == null || it.grade == filter }.sortedByDescending { it.id in ids }

    Column(Modifier.fillMaxSize().background(Color.White)) {
        Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp, bottom = 8.dp)) {
            Box(Modifier.size(44.dp).align(Alignment.CenterStart).tap(onClick = onDismiss), contentAlignment = Alignment.Center) {
                SymbolIcon(Icons.AutoMirrored.Filled.ArrowBack, DexInk, 24.dp, contentDescription = "닫기")
            }
            Text("보물 도감", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DexInk, modifier = Modifier.align(Alignment.Center))
            Text("서울대", fontSize = 17.sp, color = DexGray, modifier = Modifier.align(Alignment.CenterEnd))
        }
        Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp).height(1.dp).background(hex(0xe6e9ec)))
        // 진행률
        val count = ids.size
        val total = Landmark.all.size
        Column(Modifier.padding(horizontal = 12.dp).padding(top = 18.dp, bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text("발견한 보물", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = DexInk)
                Spacer(Modifier.weight(1f))
                Text("$count / $total", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = DexInk)
            }
            Box(Modifier.fillMaxWidth().height(6.dp).background(hex(0xe3e6e9), CircleShape)) {
                Box(Modifier.fillMaxWidth(if (total > 0) count / total.toFloat() else 0f).fillMaxHeight().background(DexGreen, CircleShape))
            }
        }
        // 등급 탭
        Row(Modifier.padding(horizontal = 12.dp)) {
            (listOf<TreasureGrade?>(null) + TreasureGrade.entries).forEach { grade ->
                val on = filter == grade
                Column(Modifier.weight(1f).tap { filter = grade }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(grade?.title ?: "전체", fontSize = 19.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Medium, color = if (on) DexGreen else DexGray)
                    Box(Modifier.fillMaxWidth().height(3.dp).background(if (on) DexGreen else Color.Transparent))
                }
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(hex(0xe6e9ec)))
        Column(Modifier.weight(1f).fillMaxWidth().background(DexPage).verticalScroll(rememberScrollState()).padding(horizontal = 12.dp).padding(top = 16.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)) {
            shown.chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    row.forEach { treasure ->
                        Box(Modifier.weight(1f).tap { selected = treasure }) { DexCard(treasure, treasure.id in ids) }
                    }
                    repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
            Text("미발견 보물을 눌러 단서를 확인하세요", fontSize = 14.sp, color = DexGray, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp))
        }
    }

    selected?.let { treasure ->
        ModalBottomSheet(onDismissRequest = { selected = null }, containerColor = Color.White) {
            TreasureDetailSheet(treasure, treasure.id in ids, here, onTestAR = { selected = null; onTestAR(treasure) })
        }
    }
}

@Composable
private fun DexCard(treasure: Landmark, done: Boolean) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(1f).shadow(2.dp, RoundedCornerShape(18.dp)).background(Color.White, RoundedCornerShape(18.dp))
            .padding(if (done) 12.dp else 22.dp)) {
            TreasureIcon(treasure, Modifier.fillMaxSize(), locked = !done)
        }
        Spacer(Modifier.height(8.dp))
        Text(if (done) treasure.name else "미발견", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = DexInk, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (!done) Text(treasure.clue, fontSize = 14.sp, color = DexGray, maxLines = 2, textAlign = TextAlign.Center, overflow = TextOverflow.Ellipsis)
        Text(treasure.grade.title, fontSize = 15.sp, fontWeight = if (treasure.grade == TreasureGrade.COMMON) FontWeight.Normal else FontWeight.SemiBold,
            color = treasure.grade.color)
    }
}

/** 도감 칸을 누르면 뜨는 상세. 미발견이면 단서와 거리만 보여준다. */
@Composable
private fun TreasureDetailSheet(treasure: Landmark, done: Boolean, here: CampusCoordinate?, onTestAR: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 32.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        TreasureIcon(treasure, Modifier.padding(top = 8.dp).size(140.dp), locked = !done)
        Text(if (done) treasure.name else "미발견 보물", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = DexInk)
        Text(treasure.grade.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = treasure.grade.color)
        if (done) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                SymbolIcon(Icons.Filled.PinDrop, DexGray, 17.dp)
                Text(treasure.place, fontSize = 15.sp, color = DexGray)
            }
            Text(treasure.blurb, fontSize = 16.sp, color = DexInk, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 4.dp))
        } else {
            Column(Modifier.fillMaxWidth().background(DexPage, RoundedCornerShape(16.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    SymbolIcon(Icons.Filled.Lightbulb, DexGreen, 17.dp)
                    Text("단서", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DexGreen)
                }
                Text(treasure.clue, fontSize = 16.sp, color = DexInk)
            }
            Text(distanceText(treasure, here), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DexGreen)
        }
        if (org.chargajoe.chajajwo.BuildConfig.DEBUG) {
            Text("AR 테스트", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DexGreen, modifier = Modifier.padding(top = 4.dp).tap(onClick = onTestAR).padding(8.dp))
        }
    }
}

private fun distanceText(treasure: Landmark, here: CampusCoordinate?): String {
    if (here == null || !here.isValid) return "가까이 가면 지도에 여우가 나타나요"
    val meters = treasure.coordinate.distanceTo(here).toInt()
    if (meters <= Landmark.COLLECT_RADIUS) return "근처예요! 지도에서 여우를 찾아 눌러보세요"
    return if (meters >= 1000) String.format(Locale.KOREA, "약 %.1fkm 떨어져 있어요", meters / 1000.0) else "약 ${meters}m 떨어져 있어요"
}

/** 홈에서 쓰는 전체 화면 래퍼. */
@Composable
fun TreasureScreens(collection: LandmarkCollection, here: CampusCoordinate?, showDex: Boolean, arLandmark: Landmark?,
                    onCloseDex: () -> Unit, onOpenAR: (Landmark) -> Unit, onCloseAR: () -> Unit) {
    if (showDex) FullScreenDialog(onDismiss = onCloseDex) { LandmarkDexView(collection, here, onCloseDex, onOpenAR) }
    if (arLandmark != null) FullScreenDialog(onDismiss = onCloseAR, edgeToEdge = true) { LandmarkARScreen(arLandmark, collection, onCloseAR) }
}
