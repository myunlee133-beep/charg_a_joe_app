package org.chargajoe.chajajwo.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import org.chargajoe.chajajwo.Store

@Composable
fun ContentView() {
    val app = LocalApp.current
    val store = app.store
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val lifeState by lifecycle.currentStateAsState()
    val active = lifeState.isAtLeast(Lifecycle.State.RESUMED)

    val shouldTrackShuttle = active && store.tab == Store.Tab.HOME &&
        (store.homeFilter == Store.HomeFilter.ALL || store.homeFilter == Store.HomeFilter.SHUTTLE)
    LaunchedEffect(shouldTrackShuttle) { if (shouldTrackShuttle) app.shuttle.run() }
    LaunchedEffect(active) { if (active) store.refreshDining() }

    Box(Modifier.fillMaxSize().background(Color.White)) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                // TabView의 다섯 칸 제한 없이, 방문한 화면과 상태를 유지한다.
                RetainedTab(selected = store.tab == Store.Tab.HOME) {
                    if (store.showDining) DiningScreen() else HomeScreen()
                }
                RetainedTab(selected = store.tab == Store.Tab.DINING) { DiningScreen() }
            }
            Row(
                Modifier.fillMaxWidth()
                    .shadow(5.dp, ambientColor = Color.Black.copy(alpha = 0.06f), spotColor = Color.Black.copy(alpha = 0.06f))
                    .background(Cj.surface)
                    .windowInsetsPadding(WindowInsets.navigationBars)
                    .padding(top = 9.dp, bottom = 5.dp),
            ) {
                TabButton(store, Store.Tab.HOME, "홈", Sym.home)
                TabButton(store, Store.Tab.DINING, "식당", Sym.forkKnife)
            }
        }
        AnimatedVisibility(
            visible = store.toastText != null,
            enter = slideInVertically { it } + fadeIn(),
            exit = slideOutVertically { it } + fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 100.dp).windowInsetsPadding(WindowInsets.navigationBars).zIndex(10f),
        ) {
            var last by remember { mutableStateOf("") }
            store.toastText?.let { last = it }
            Text(last, style = Type.subheadline, color = Color.White,
                modifier = Modifier.background(hex(0x1b2328).copy(alpha = 0.92f), RoundedCornerShape(12.dp)).padding(horizontal = 16.dp, vertical = 10.dp))
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.TabButton(store: Store, value: Store.Tab, title: String, icon: ImageVector) {
    val on = store.tab == value
    Column(
        Modifier.weight(1f).heightIn(min = 44.dp).tap { store.tab = value }
            .semantics { selected = on; contentDescription = "main-tab-$title" },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        SymbolIcon(icon, if (on) Cj.teal else Cj.sub, 22.dp)
        Text(title, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = if (on) Cj.teal else Cj.sub, maxLines = 1)
    }
}

@Composable
private fun RetainedTab(selected: Boolean, content: @Composable () -> Unit) {
    var visited by remember { mutableStateOf(selected) }
    if (selected) visited = true
    if (selected || visited) {
        // 같은 자리에서 계속 그려야 지도·스크롤 상태가 유지된다. 숨은 탭은 아래에 깔려 터치를 받지 않는다.
        Box(Modifier.fillMaxSize().alpha(if (selected) 1f else 0f).zIndex(if (selected) 1f else 0f), propagateMinConstraints = true) {
            content()
        }
    }
}
