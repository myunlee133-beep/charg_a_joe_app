package org.chargajoe.chajajwo.data

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log
import kotlinx.serialization.json.Json
import java.text.Normalizer
import java.util.Locale

/** iOS의 Bundle 리소스(Core/Resources)를 assets에서 읽는다. */
@SuppressLint("StaticFieldLeak")
object PlaceResources {
    lateinit var context: Context
        private set

    val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        explicitNulls = false
        coerceInputValues = true
    }

    fun init(context: Context) {
        this.context = context.applicationContext
    }

    fun readText(name: String): String? = try {
        context.assets.open(name).bufferedReader(Charsets.UTF_8).use { it.readText() }
    } catch (e: Exception) {
        Log.w("PlaceResources", "could not load $name: $e")
        null
    }

    inline fun <reified T> decode(name: String): T? {
        val text = readText("$name.json") ?: return null
        return try {
            json.decodeFromString<T>(text)
        } catch (e: Exception) {
            Log.w("PlaceResources", "could not decode $name: $e")
            null
        }
    }

    /** iOS 에셋 이름(예: BuildingPhoto-snu-1, ARFox)을 drawable 리소스 이름으로 바꾼다. */
    fun drawableName(asset: String): String =
        asset.replace(Regex("(?<!^)(?=[A-Z])"), "_").lowercase(Locale.ROOT)
            .replace('-', '_').replace(Regex("_+"), "_")

    @SuppressLint("DiscouragedApi")
    fun drawableId(asset: String?): Int? {
        if (asset == null) return null
        val id = context.resources.getIdentifier(drawableName(asset), "drawable", context.packageName)
        return if (id == 0) null else id
    }
}

/** Swift `folding([.caseInsensitive, .widthInsensitive, .diacriticInsensitive])` + 공백 제거. */
fun String.compactKey(): String {
    val width = Normalizer.normalize(this, Normalizer.Form.NFKC)
    val decomposed = Normalizer.normalize(width, Normalizer.Form.NFD)
    val sb = StringBuilder()
    for (ch in decomposed) {
        // 결합 분음 부호만 제거한다. 한글 자모(NFD)는 다시 합친다.
        if (Character.getType(ch) == Character.NON_SPACING_MARK.toInt() && ch.code in 0x0300..0x036F) continue
        sb.append(ch)
    }
    return Normalizer.normalize(sb.toString(), Normalizer.Form.NFC).lowercase(Locale.ROOT).filterNot { it.isWhitespace() }
}

/** Swift `localizedStandardCompare`에 가까운 자연 정렬(숫자는 수 값으로 비교). */
val naturalOrder: Comparator<String> = Comparator { a, b ->
    var i = 0
    var j = 0
    while (i < a.length && j < b.length) {
        val ca = a[i]
        val cb = b[j]
        if (ca.isDigit() && cb.isDigit()) {
            var ei = i; while (ei < a.length && a[ei].isDigit()) ei++
            var ej = j; while (ej < b.length && b[ej].isDigit()) ej++
            val na = a.substring(i, ei).trimStart('0')
            val nb = b.substring(j, ej).trimStart('0')
            if (na.length != nb.length) return@Comparator na.length - nb.length
            val c = na.compareTo(nb)
            if (c != 0) return@Comparator c
            i = ei; j = ej
        } else {
            val c = ca.lowercaseChar().compareTo(cb.lowercaseChar())
            if (c != 0) return@Comparator c
            i++; j++
        }
    }
    (a.length - i) - (b.length - j)
}

fun Int.won(): String = String.format(Locale.KOREA, "%,d", this)
