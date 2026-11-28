package org.chargajoe.chajajwo.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import org.chargajoe.chajajwo.ChajajwoApp
import org.chargajoe.chajajwo.data.CampusAmenityKind
import org.chargajoe.chajajwo.data.PlaceType

val LocalApp = staticCompositionLocalOf<ChajajwoApp> { error("ChajajwoApp not provided") }

fun hex(value: Long): Color = Color(0xFF000000 or value)

/** iOS Color+cj 팔레트(앱은 라이트 모드 고정). */
object Cj {
    val teal = hex(0x0f7f74)
    val orange = hex(0xf26b1d)
    val blue = hex(0x1e7be0)
    val berry = hex(0xa63d66)
    val shuttle = hex(0x365fc7)
    val surface = Color.White                 // secondarySystemGroupedBackground
    val inset = hex(0xF2F2F7)                 // tertiarySystemGroupedBackground
    val grouped = hex(0xF2F2F7)               // systemGroupedBackground
    val sub = hex(0x6b767d)
    val line = hex(0xC6C6C8)                  // separator
    val handle = hex(0xd4d9dc)
    val tealText = hex(0x0f7f74)
    val orangeText = hex(0xc4500f)
    val blueText = hex(0x1e7be0)
    val berryText = hex(0xa63d66)
    val orangeFill = hex(0xfdd3b8)
    val successFill = hex(0xe4f3f1)
    val successText = hex(0x0b6158)
    val primary = hex(0x000000)
    val secondary = hex(0x3C3C43).copy(alpha = 0.6f)
    val tertiary = hex(0x3C3C43).copy(alpha = 0.3f)
    val ink = hex(0x1b2328)
}

object BuildingDesign {
    val green = hex(0x00866b)
    val mint = hex(0xe5f5ef)
    val line = hex(0xe4eae7)
    val canvas = hex(0xf8faf9)
}

val PlaceType.color: Color get() = when (this) { PlaceType.HUB -> Cj.teal; PlaceType.FOOD -> Cj.berry; PlaceType.STOP -> Cj.shuttle }

val CampusAmenityKind.ink: Color
    get() = when (this) {
        CampusAmenityKind.PHARMACY, CampusAmenityKind.HEALTH -> hex(0xa43f5b)
        CampusAmenityKind.CONVENIENCE -> hex(0x32699c)
        CampusAmenityKind.CAFE -> hex(0x89613a)
        else -> hex(0x006f58)
    }
val CampusAmenityKind.wash: Color get() = ink.copy(alpha = 0.09f)

/** iOS Dynamic Type 기본 크기. */
object Type {
    val largeTitle = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold, lineHeight = 41.sp)
    val title = TextStyle(fontSize = 28.sp, lineHeight = 34.sp)
    val title2 = TextStyle(fontSize = 22.sp, lineHeight = 28.sp)
    val title3 = TextStyle(fontSize = 20.sp, lineHeight = 25.sp)
    val headline = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, lineHeight = 22.sp)
    val body = TextStyle(fontSize = 17.sp, lineHeight = 22.sp)
    val subheadline = TextStyle(fontSize = 15.sp, lineHeight = 20.sp)
    val footnote = TextStyle(fontSize = 13.sp, lineHeight = 18.sp)
    val caption = TextStyle(fontSize = 12.sp, lineHeight = 16.sp)
    val caption2 = TextStyle(fontSize = 11.sp, lineHeight = 13.sp)
}

fun TextStyle.w(weight: FontWeight) = copy(fontWeight = weight)

@Composable
fun ChajajwoTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = Cj.teal,
            onPrimary = Color.White,
            secondary = Cj.orange,
            background = Color.White,
            surface = Color.White,
            onSurface = Color.Black,
            onBackground = Color.Black,
        ),
        content = content,
    )
}
