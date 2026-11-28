package org.chargajoe.chajajwo.ui.map

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.VectorPainter
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import org.chargajoe.chajajwo.R
import org.chargajoe.chajajwo.data.CampusAmenityKind
import org.chargajoe.chajajwo.data.PlaceType
import org.chargajoe.chajajwo.ui.Cj
import org.chargajoe.chajajwo.ui.color
import org.chargajoe.chajajwo.ui.hex
import org.chargajoe.chajajwo.ui.ink
import kotlin.math.ceil
import kotlin.math.max

/** 지도 핀에 쓰는 Material 아이콘(Compose VectorPainter). */
class PinPainters(
    val building: VectorPainter,
    val amenity: Map<CampusAmenityKind, VectorPainter>,
)

/** 비트맵과 좌표 기준점(0~1). */
class PinImage(val bitmap: Bitmap, val anchorX: Float, val anchorY: Float)

/**
 * iOS가 SwiftUI 뷰를 ImageRenderer로 그려 만든 핀 이미지를 Android Canvas로 그린다.
 * 모든 크기는 iOS pt(=dp) 기준이고 기기 밀도로 픽셀을 만든다.
 */
class PinBitmaps(private val context: Context, private val painters: PinPainters) {
    private val d = context.resources.displayMetrics.density
    private fun px(v: Float) = v * d
    private val cache = HashMap<String, PinImage>()

    private fun bitmap(widthDp: Float, heightDp: Float): Pair<Bitmap, Canvas> {
        val b = Bitmap.createBitmap(max(1, ceil(px(widthDp)).toInt()), max(1, ceil(px(heightDp)).toInt()), Bitmap.Config.ARGB_8888)
        return b to Canvas(b)
    }

    private fun resource(id: Int): Bitmap? = BitmapFactory.decodeResource(context.resources, id)

    private fun drawVector(canvas: Canvas, painter: VectorPainter, leftDp: Float, topDp: Float, sizeDp: Float, color: Int) {
        val size = px(sizeDp)
        canvas.save()
        canvas.translate(px(leftDp), px(topDp))
        CanvasDrawScope().draw(Density(d), LayoutDirection.Ltr, androidx.compose.ui.graphics.Canvas(canvas), Size(size, size)) {
            with(painter) { draw(Size(size, size), colorFilter = ColorFilter.tint(androidx.compose.ui.graphics.Color(color))) }
        }
        canvas.restore()
    }

    private fun textPaint(sizeDp: Float, color: Int, bold: Boolean = true) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = px(sizeDp)
        this.color = color
        typeface = Typeface.create(Typeface.DEFAULT, if (bold) Typeface.BOLD else Typeface.NORMAL)
    }

    /** 식당·정류장 핀. 식당은 이름표를 아이콘 아래에 그린다. iOS PinIcon(markerScale 0.8). */
    fun placePin(type: PlaceType, selected: Boolean, label: String?): PinImage = cache.getOrPut("place-$type-$selected-$label") {
        val scale = 0.8f
        val pinW = 32 * scale
        val pinH = 40 * scale
        val text = label?.let { textPaint(11f, hex(0x1b2328).toArgb()) }
        val textWidthDp = if (label != null && text != null) text.measureText(label) / d else 0f
        val capsuleW = if (label != null) textWidthDp + 14 else 0f
        val capsuleH = if (label != null) 11f * 1.3f + 6 else 0f
        val width = max(pinW, capsuleW + 3) + 2
        val height = pinH + (if (label != null) capsuleH + 4 else 0f) + 2
        val (bmp, canvas) = bitmap(width, height)
        val icon = resource(if (type == PlaceType.FOOD) R.drawable.restaurant_pin else R.drawable.shuttle_stop)
        if (icon != null) {
            val left = (width - pinW) / 2
            val shadow = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                setShadowLayer(px(1f), 0f, px(1f), android.graphics.Color.argb(if (selected) 61 else 36, 0, 0, 0))
            }
            canvas.drawBitmap(icon, null, RectF(px(left), px(1f), px(left + pinW), px(1f + pinH)), shadow)
        }
        if (label != null && text != null) {
            val top = 1 + pinH + 2
            val left = (width - capsuleW) / 2
            val rect = RectF(px(left), px(top), px(left + capsuleW), px(top + capsuleH))
            canvas.drawRoundRect(rect, rect.height() / 2, rect.height() / 2, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE })
            val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = px(if (selected) 1.5f else 1f)
                color = type.color.copy(alpha = if (selected) 0.9f else 0.5f).toArgb()
            }
            canvas.drawRoundRect(rect, rect.height() / 2, rect.height() / 2, stroke)
            val fm = text.fontMetrics
            val baseline = rect.centerY() - (fm.ascent + fm.descent) / 2
            canvas.drawText(label, px(left + 7), baseline, text)
        }
        // 이름표가 붙어도 핀 끝(37pt × 0.8)을 실제 좌표에 고정한다.
        PinImage(bmp, 0.5f, (1 + 37 * scale) / height)
    }

    /** 검색·지도에서 고른 건물 전용 핀. */
    fun buildingPin(): PinImage = cache.getOrPut("building") {
        val w = 33f + 18
        val h = 33f + 8 + 18 - 3
        val (bmp, canvas) = bitmap(w, h)
        val cx = w / 2
        val cy = 9 + 16.5f
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Cj.teal.toArgb() }
        val tri = Path().apply {
            moveTo(px(cx - 5), px(9 + 33f - 2)); lineTo(px(cx + 5), px(9 + 33f - 2)); lineTo(px(cx), px(9 + 33f + 5)); close()
        }
        canvas.drawPath(tri, fill)
        canvas.drawCircle(px(cx), px(cy), px(16.5f), Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE })
        canvas.drawCircle(px(cx), px(cy), px(13.5f), fill)
        drawVector(canvas, painters.building, cx - 8, cy - 8, 16f, android.graphics.Color.WHITE)
        PinImage(bmp, 0.5f, (9 + 33f + 5) / h)
    }

    /** 편의시설 핀: 원형 아이콘 + 개수 + (확대 시) 이름. */
    fun amenityPin(kind: CampusAmenityKind, count: Int, name: String?): PinImage = cache.getOrPut("amenity-$kind-$count-$name") {
        val text = name?.let { textPaint(12f, android.graphics.Color.BLACK, bold = true) }
        val nameW = if (name != null && text != null) minOf(140f, text.measureText(name) / d) else 0f
        val innerW = 34f + (if (name != null) 6 + nameW + 9 else 0f)
        val w = innerW + 6 + 10
        val h = 34f + 6 + 10
        val (bmp, canvas) = bitmap(w, h)
        val capsule = RectF(px(5f), px(5f), px(5f + innerW + 6), px(5f + 40))
        val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.WHITE
            setShadowLayer(px(3f), 0f, px(2f), android.graphics.Color.argb(38, 0, 0, 0))
        }
        canvas.drawRoundRect(capsule, capsule.height() / 2, capsule.height() / 2, bg)
        val cx = 5 + 3 + 17f
        val cy = 5 + 3 + 17f
        canvas.drawCircle(px(cx), px(cy), px(17f), Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE })
        canvas.drawCircle(px(cx), px(cy), px(15f), Paint(Paint.ANTI_ALIAS_FLAG).apply { color = kind.ink.toArgb() })
        painters.amenity[kind]?.let { drawVector(canvas, it, cx - 9, cy - 9, 18f, android.graphics.Color.WHITE) }
        if (count > 1) {
            val badge = textPaint(10f, kind.ink.toArgb())
            val label = count.toString()
            val bw = max(16f, badge.measureText(label) / d + 6)
            val bx = cx + 17 + 5 - bw / 2 - 3
            val by = cy - 17 - 4 + 8 - 3
            canvas.drawCircle(px(bx), px(by), px(bw / 2), Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE })
            val fm = badge.fontMetrics
            canvas.drawText(label, px(bx) - badge.measureText(label) / 2, px(by) - (fm.ascent + fm.descent) / 2, badge)
        }
        if (name != null && text != null) {
            var shown = name
            while (text.measureText(shown) / d > 140 && shown.length > 1) shown = shown.dropLast(1)
            if (shown != name) shown = shown.dropLast(1) + "…"
            val fm = text.fontMetrics
            canvas.drawText(shown, px(5 + 3 + 34 + 6f), px(cy) - (fm.ascent + fm.descent) / 2, text)
        }
        // 이름표 중심이 아니라 둥근 아이콘이 건물 좌표에 놓인다.
        PinImage(bmp, minOf(1f, 25 / w), 0.5f)
    }

    fun userDot(): PinImage = cache.getOrPut("user-dot") {
        val (bmp, canvas) = bitmap(80f, 80f)
        val blue = android.graphics.Color.rgb(31, 120, 245)
        canvas.drawCircle(px(40f), px(40f), px(10.5f), Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.WHITE
            setShadowLayer(px(3f), 0f, px(1f), android.graphics.Color.argb(77, 0, 0, 0))
        })
        canvas.drawCircle(px(40f), px(40f), px(7.5f), Paint(Paint.ANTI_ALIAS_FLAG).apply { color = blue })
        PinImage(bmp, 0.5f, 0.5f)
    }

    /** 반투명 부채꼴은 북쪽(0)을 가리킨다. 지도가 나침반 방향으로 돌린다. */
    fun userDirection(): PinImage = cache.getOrPut("user-direction") {
        val (bmp, canvas) = bitmap(80f, 80f)
        val path = Path().apply {
            moveTo(px(40f), px(40f)); lineTo(px(19f), px(9f)); quadTo(px(40f), px(-1f), px(61f), px(9f)); close()
        }
        canvas.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.argb(61, 31, 120, 245) })
        PinImage(bmp, 0.5f, 0.5f)
    }

    fun shuttle(): PinImage = cache.getOrPut("shuttle") {
        val (bmp, canvas) = bitmap(18f, 27f)
        resource(R.drawable.campus_shuttle)?.let { canvas.drawBitmap(it, null, RectF(0f, 0f, px(18f), px(27f)), Paint(Paint.FILTER_BITMAP_FLAG)) }
        PinImage(bmp, 0.5f, 0.5f)
    }

    fun fox(): PinImage = cache.getOrPut("fox") {
        val (bmp, canvas) = bitmap(64f, 76f)
        resource(R.drawable.a_r_fox)?.let { canvas.drawBitmap(it, null, RectF(0f, 0f, px(64f), px(76f)), Paint(Paint.FILTER_BITMAP_FLAG)) }
        PinImage(bmp, 0.5f, 1f)
    }

    /** 다음 수업 동선 미니 지도용 점 핀. */
    fun dot(color: Int, sizeDp: Float = 18f): PinImage = cache.getOrPut("dot-$color-$sizeDp") {
        val (bmp, canvas) = bitmap(sizeDp + 8, sizeDp + 8)
        val c = (sizeDp + 8) / 2
        canvas.drawCircle(px(c), px(c), px(sizeDp / 2), Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = android.graphics.Color.WHITE
            setShadowLayer(px(2f), 0f, px(1f), android.graphics.Color.argb(70, 0, 0, 0))
        })
        canvas.drawCircle(px(c), px(c), px(sizeDp / 2 - 3), Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color })
        PinImage(bmp, 0.5f, 0.5f)
    }
}
