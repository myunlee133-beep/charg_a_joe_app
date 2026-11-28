package org.chargajoe.chajajwo.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import org.chargajoe.chajajwo.data.PlaceResources
import org.chargajoe.chajajwo.data.PlaceType

val NoRipple = MutableInteractionSource()

fun Modifier.tap(enabled: Boolean = true, onClick: () -> Unit): Modifier =
    clickable(enabled = enabled, interactionSource = null, indication = null, onClick = onClick)

/** SF Symbol 대신 Material 아이콘. size는 iOS font size(pt)에 맞춘다. */
@Composable
fun SymbolIcon(icon: ImageVector, tint: Color = Color.Unspecified, size: Dp = 17.dp, modifier: Modifier = Modifier, contentDescription: String? = null) {
    Icon(icon, contentDescription, modifier = modifier.size(size), tint = if (tint == Color.Unspecified) Color.Black else tint)
}

/** Label(title, systemImage:) */
@Composable
fun LabelText(text: String, icon: ImageVector, style: TextStyle = Type.subheadline, color: Color = Color.Black, iconColor: Color = color,
              modifier: Modifier = Modifier, spacing: Dp = 6.dp, maxLines: Int = Int.MAX_VALUE) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(spacing)) {
        SymbolIcon(icon, iconColor, size = (style.fontSize.value * 1.15f).dp)
        Text(text, style = style, color = color, maxLines = maxLines, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun PlaceIcon(type: PlaceType, size: Dp = 44.dp) {
    Box(Modifier.size(size).background(type.color, CircleShape), contentAlignment = Alignment.Center) {
        SymbolIcon(Sym.place(type), Color.White, size = size * 0.48f)
    }
}

@Composable
fun Badge(text: String, color: Color) {
    Text(text, style = Type.caption, color = color,
        modifier = Modifier.background(color.copy(alpha = 0.12f), RoundedCornerShape(8.dp)).padding(horizontal = 8.dp, vertical = 2.dp))
}

enum class BtnStyle { ORANGE_FILL, ORANGE_LINE, TEAL_FILL, TEAL_LINE }

@Composable
fun BigLabel(text: String, style: BtnStyle, modifier: Modifier = Modifier) {
    val fg = when (style) { BtnStyle.ORANGE_FILL, BtnStyle.ORANGE_LINE -> Cj.orangeText; BtnStyle.TEAL_FILL -> Color.White; BtnStyle.TEAL_LINE -> Cj.tealText }
    val bg = when (style) { BtnStyle.ORANGE_FILL -> Cj.orangeFill; BtnStyle.TEAL_FILL -> Cj.teal; else -> Color.Transparent }
    val stroke = when (style) { BtnStyle.ORANGE_LINE -> Cj.orangeText; BtnStyle.TEAL_LINE -> Cj.tealText; else -> null }
    val shape = RoundedCornerShape(14.dp)
    Box(modifier.fillMaxWidth().heightIn(min = 52.dp).background(bg, shape)
        .then(if (stroke != null) Modifier.border(1.5.dp, stroke, shape) else Modifier), contentAlignment = Alignment.Center) {
        Text(text, style = Type.body.w(FontWeight.Bold), color = fg)
    }
}

enum class SheetDetent { COLLAPSED, NORMAL, EXPANDED }

/**
 * 지도 하단 시트 공통 틀. 손잡이·헤더를 위아래로 쓸거나 손잡이를 눌러 단계를 바꾼다. 접힘이면 헤더만 보인다.
 */
@Composable
fun SwipeSheet(
    detent: SheetDetent,
    onDetentChange: (SheetDetent) -> Unit,
    normalHeight: Dp? = null,
    expandedHeightLimit: Dp? = null,
    header: @Composable ColumnScope.() -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val expandedHeight = minOf(580.dp, screenHeight * 0.65f, expandedHeightLimit ?: 10_000.dp)
    fun step(up: Boolean) {
        onDetentChange(when (detent) {
            SheetDetent.COLLAPSED -> if (up) SheetDetent.NORMAL else SheetDetent.COLLAPSED
            SheetDetent.NORMAL -> if (up) SheetDetent.EXPANDED else SheetDetent.COLLAPSED
            SheetDetent.EXPANDED -> if (!up) SheetDetent.NORMAL else SheetDetent.EXPANDED
        })
    }
    val shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
    val heightModifier = when (detent) {
        SheetDetent.EXPANDED -> Modifier.height(expandedHeight)
        SheetDetent.NORMAL -> if (normalHeight != null) Modifier.height(normalHeight) else Modifier
        SheetDetent.COLLAPSED -> Modifier
    }
    Column(
        Modifier.fillMaxWidth()
            .shadow(10.dp, shape, ambientColor = Color.Black.copy(alpha = 0.13f), spotColor = Color.Black.copy(alpha = 0.13f))
            .background(Cj.surface, shape)
            .animateContentSize(tween(250))
            .then(heightModifier)
            .padding(horizontal = 18.dp).padding(bottom = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        var dragTotal by remember { mutableStateOf(0f) }
        Column(
            Modifier.fillMaxWidth().pointerInput(detent) {
                detectVerticalDragGestures(
                    onDragStart = { dragTotal = 0f },
                    onDragEnd = { if (kotlin.math.abs(dragTotal) > 12) step(dragTotal < 0) },
                ) { _, amount -> dragTotal += amount }
            },
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(Modifier.fillMaxWidth().height(20.dp).tap { step(detent != SheetDetent.EXPANDED) }, contentAlignment = Alignment.Center) {
                Box(Modifier.width(40.dp).height(4.dp).background(Cj.handle, CircleShape))
            }
            header()
        }
        if (detent != SheetDetent.COLLAPSED) content()
    }
}

@Composable
fun BuildingSurface(padding: Dp = 16.dp, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Column(
        modifier.fillMaxWidth()
            .shadow(3.dp, shape, ambientColor = Color.Black.copy(alpha = 0.03f), spotColor = Color.Black.copy(alpha = 0.03f))
            .background(Cj.surface, shape)
            .border(1.dp, BuildingDesign.line.copy(alpha = 0.8f), shape)
            .padding(padding),
        content = content,
    )
}

@Composable
fun BuildingEmptyCard(icon: ImageVector, title: String, text: String) {
    Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SymbolIcon(icon, BuildingDesign.green, 26.dp)
        Text(title, style = Type.headline)
        Text(text, style = Type.subheadline, color = Cj.secondary, textAlign = TextAlign.Center)
    }
}

/** ContentUnavailableView */
@Composable
fun ContentUnavailable(title: String, icon: ImageVector, description: String? = null, modifier: Modifier = Modifier, actions: (@Composable () -> Unit)? = null) {
    Column(modifier.fillMaxWidth().padding(vertical = 32.dp, horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SymbolIcon(icon, Cj.secondary, 44.dp)
        Spacer(Modifier.height(4.dp))
        Text(title, style = Type.title3.w(FontWeight.Bold), textAlign = TextAlign.Center)
        if (description != null) Text(description, style = Type.subheadline, color = Cj.secondary, textAlign = TextAlign.Center)
        if (actions != null) { Spacer(Modifier.height(8.dp)); actions() }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TopicFlowLayout(spacing: Dp = 8.dp, content: @Composable () -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(spacing), verticalArrangement = Arrangement.spacedBy(spacing)) { content() }
}

/** pickerStyle(.segmented) */
@Composable
fun <T> SegmentedPicker(options: List<T>, selected: T, label: (T) -> String, modifier: Modifier = Modifier, onSelect: (T) -> Unit) {
    Row(modifier.fillMaxWidth().height(34.dp).background(hex(0x767680).copy(alpha = 0.12f), RoundedCornerShape(9.dp)).padding(2.dp)) {
        options.forEach { option ->
            val on = option == selected
            Box(
                Modifier.weight(1f).fillMaxSize()
                    .then(if (on) Modifier.shadow(2.dp, RoundedCornerShape(7.dp)).background(Color.White, RoundedCornerShape(7.dp)) else Modifier)
                    .tap { onSelect(option) },
                contentAlignment = Alignment.Center,
            ) {
                Text(label(option), style = Type.footnote.w(if (on) FontWeight.SemiBold else FontWeight.Medium), maxLines = 1)
            }
        }
    }
}

/** 검색 입력칸(iOS TextField + 돋보기 + 지우기). */
@Composable
fun SearchField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    background: Color = Cj.inset,
    height: Dp = 44.dp,
    iconColor: Color = Cj.sub,
    onSearch: () -> Unit = {},
    leading: Boolean = true,
) {
    Row(
        modifier.fillMaxWidth().height(height).background(background, RoundedCornerShape(12.dp)).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (leading) SymbolIcon(Sym.search, iconColor, 18.dp)
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (value.isEmpty()) Text(placeholder, style = Type.body, color = Cj.tertiary.copy(alpha = 0.6f), maxLines = 1)
            BasicTextField(
                value = value, onValueChange = onValueChange, singleLine = true,
                textStyle = Type.body.copy(color = Color.Black),
                cursorBrush = SolidColor(Cj.teal),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { onSearch() }),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (value.isNotEmpty()) {
            SymbolIcon(Sym.xmarkCircle, Cj.sub, 18.dp, Modifier.tap { onValueChange("") }, "검색어 지우기")
        }
    }
}

/** 화면 이동 스택. iOS NavigationStack + NavigationLink 대응. */
class Navigator {
    data class Entry(val title: String, val content: @Composable () -> Unit, val actions: (@Composable RowScope.() -> Unit)? = null)
    val stack = mutableStateListOf<Entry>()
    fun push(title: String, actions: (@Composable RowScope.() -> Unit)? = null, content: @Composable () -> Unit) { stack.add(Entry(title, content, actions)) }
    fun pop() { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }
    fun popToRoot() { stack.clear() }
}

val LocalNavigator = staticCompositionLocalOf<Navigator?> { null }

/** NavigationStack: 루트 화면 위에 push된 화면을 그린다. */
@Composable
fun NavStack(navigator: Navigator, modifier: Modifier = Modifier, root: @Composable () -> Unit) {
    androidx.compose.runtime.CompositionLocalProvider(LocalNavigator provides navigator) {
        Box(modifier) {
            if (navigator.stack.isEmpty()) root()
            else {
                val top = navigator.stack.last()
                BackHandler { navigator.pop() }
                Column(Modifier.fillMaxSize().background(Color.White)) {
                    NavBar(title = top.title, onBack = { navigator.pop() }, actions = top.actions)
                    Box(Modifier.weight(1f)) { top.content() }
                }
            }
        }
    }
}

/** navigationBarTitleDisplayMode(.inline) 상단 바. */
@Composable
fun NavBar(title: String, onBack: (() -> Unit)? = null, backLabel: String? = null, subtitle: String? = null,
           leading: (@Composable RowScope.() -> Unit)? = null, actions: (@Composable RowScope.() -> Unit)? = null) {
    Box(Modifier.fillMaxWidth().height(48.dp).background(Color.White)) {
        Row(Modifier.align(Alignment.CenterStart).padding(start = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            if (leading != null) leading()
            else if (onBack != null) {
                Row(Modifier.heightIn(min = 44.dp).tap(onClick = onBack).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    SymbolIcon(Sym.chevronLeft, Cj.tealText, 28.dp, contentDescription = "뒤로")
                    if (backLabel != null) Text(backLabel, style = Type.body, color = Cj.tealText)
                }
            }
        }
        Column(Modifier.align(Alignment.Center).widthIn(max = 220.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            if (title.isNotEmpty()) Text(title, style = Type.headline, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) Text(subtitle, style = Type.caption, color = Cj.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (actions != null) Row(Modifier.align(Alignment.CenterEnd).padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)) { actions() }
    }
}

@Composable
fun NavLink(title: String, modifier: Modifier = Modifier, enabled: Boolean = true, destination: @Composable () -> Unit, label: @Composable () -> Unit) {
    val nav = LocalNavigator.current
    Box(modifier.tap(enabled) { nav?.push(title, content = destination) }) { label() }
}

@Composable
fun TextButton(text: String, color: Color = Cj.tealText, style: TextStyle = Type.body, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Text(text, style = style, color = if (enabled) color else color.copy(alpha = 0.35f),
        modifier = modifier.heightIn(min = 44.dp).tap(enabled, onClick).padding(vertical = 11.dp))
}

/** Link(title, destination:) */
@Composable
fun LinkText(title: String, url: String, style: TextStyle = Type.body, modifier: Modifier = Modifier) {
    val uri = LocalUriHandler.current
    Text(title, style = style, color = Cj.tealText, modifier = modifier.heightIn(min = 36.dp).tap { runCatching { uri.openUri(url) } }.padding(vertical = 8.dp))
}

@Composable
fun PlaceSourceLink(title: String, value: String) {
    val url = org.chargajoe.chajajwo.data.PlaceDirectory.sourceURL(value) ?: return
    val uri = LocalUriHandler.current
    Row(Modifier.heightIn(min = 44.dp).tap { runCatching { uri.openUri(url) } }, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        SymbolIcon(Sym.openExternal, Cj.tealText, 18.dp)
        Text(title, style = Type.body, color = Cj.tealText)
    }
}

/** 리소스 이미지(iOS Asset). 없으면 아무것도 그리지 않는다. */
@Composable
fun AssetImage(asset: String?, modifier: Modifier = Modifier, contentScale: ContentScale = ContentScale.Fit, contentDescription: String? = null) {
    val id = remember(asset) { PlaceResources.drawableId(asset) } ?: return
    Image(painterResource(id), contentDescription, modifier, contentScale = contentScale)
}

/** List(.insetGrouped) 흉내: 회색 바탕 위 흰 카드 섹션. */
@Composable
fun GroupSection(header: String? = null, footer: String? = null, content: (@Composable ColumnScope.() -> Unit)? = null) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        if (header != null) Text(header, style = Type.footnote, color = Cj.secondary, modifier = Modifier.padding(start = 16.dp, top = 18.dp, bottom = 7.dp))
        else Spacer(Modifier.height(18.dp))
        if (content != null) {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Color.White), content = content)
        }
        if (footer != null) Text(footer, style = Type.footnote, color = Cj.secondary, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 7.dp))
    }
}

@Composable
fun GroupRow(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, showDivider: Boolean = true, chevron: Boolean = false,
             content: @Composable RowScope.() -> Unit) {
    Column {
        Row(modifier.fillMaxWidth().heightIn(min = 44.dp).then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            content()
            if (chevron) { Spacer(Modifier.width(8.dp)); SymbolIcon(Sym.chevronRight, Cj.tertiary, 20.dp) }
        }
        if (showDivider) HorizontalDivider(Modifier.padding(start = 16.dp), thickness = 0.5.dp, color = Cj.line)
    }
}

/** fullScreenCover 대응. */
@Composable
fun FullScreenDialog(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.White).windowInsetsPadding(WindowInsets.statusBars).windowInsetsPadding(WindowInsets.navigationBars)) {
            content()
        }
    }
}

/** DisclosureGroup */
@Composable
fun Disclosure(label: @Composable (Boolean) -> Unit, initiallyExpanded: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    var expanded by remember { mutableStateOf(initiallyExpanded) }
    Column(Modifier.fillMaxWidth().animateContentSize()) {
        Row(Modifier.fillMaxWidth().tap { expanded = !expanded }, verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { label(expanded) }
            SymbolIcon(if (expanded) Sym.chevronDown else Sym.chevronRight, Cj.tealText, 20.dp)
        }
        if (expanded) content()
    }
}

/** iOS .caption 크기 아이콘+텍스트 캡슐 버튼 */
@Composable
fun CapsuleChip(text: String, selected: Boolean, selectedColor: Color, modifier: Modifier = Modifier, unselectedColor: Color = Cj.inset,
                style: TextStyle = Type.subheadline.w(FontWeight.SemiBold), onClick: () -> Unit) {
    Box(modifier.heightIn(min = 44.dp).background(if (selected) selectedColor else unselectedColor, CircleShape).tap(onClick = onClick).padding(horizontal = 15.dp),
        contentAlignment = Alignment.Center) {
        Text(text, style = style, color = if (selected) Color.White else Color.Black, maxLines = 1)
    }
}

@Composable
fun VSpacer(h: Dp) = Spacer(Modifier.height(h))

@Composable
fun HSpacer(w: Dp) = Spacer(Modifier.width(w))

@Composable
fun Divider(modifier: Modifier = Modifier) = HorizontalDivider(modifier, thickness = 0.5.dp, color = Cj.line)

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MaxWidthText(text: String, style: TextStyle, color: Color = Color.Black, modifier: Modifier = Modifier) =
    Text(text, style = style, color = color, modifier = modifier.fillMaxWidth())

/** 화면 폭이 좁을 때 VStack, 넓을 때 HStack (ViewThatFits). */
@Composable
fun AdaptiveRow(content: @Composable (horizontal: Boolean) -> Unit) {
    BoxWithConstraints { content(maxWidth > 340.dp) }
}

