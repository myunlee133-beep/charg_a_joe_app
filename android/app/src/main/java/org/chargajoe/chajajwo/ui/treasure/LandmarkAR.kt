package org.chargajoe.chajajwo.ui.treasure

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.opengl.GLSurfaceView
import android.view.HapticFeedbackConstants
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.CenterFocusWeak
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import kotlinx.coroutines.delay
import org.chargajoe.chajajwo.LandmarkCollection
import org.chargajoe.chajajwo.data.Landmark
import org.chargajoe.chajajwo.ui.AssetImage
import org.chargajoe.chajajwo.ui.SymbolIcon
import org.chargajoe.chajajwo.ui.hex
import org.chargajoe.chajajwo.ui.tap
import kotlin.math.roundToInt

private val Forest = hex(0x24502f)
private val Cream = hex(0xfbf6e4)
private val Coral = hex(0xe9634a)
private val Gold = hex(0xf6c744)

private enum class Phase { SEARCHING, FOUND, OPENED }

private fun Context.findActivity(): Activity? {
    var c: Context? = this
    while (c is ContextWrapper) { if (c is Activity) return c; c = c.baseContext }
    return null
}

/** 효과음 설정(iOS @AppStorage("arSoundOn")). */
private fun soundPrefs(context: Context) = context.getSharedPreferences("cj_ar", Context.MODE_PRIVATE)

/**
 * AR 보물 찾기 화면.
 * 1. 근처: "보물이 근처에 있어요" + 단서. 단서 속 대상(ar_target_<id> 사진)을 찾는다.
 * 2. 대상을 비추면(사진이 없으면 바로): "보물 발견!" + 보물상자. 상자 탭이나 "보물 열기"로 연다.
 * 3. 열면 보물이 튀어나오고 도감에 등록된다.
 */
@Composable
fun LandmarkARScreen(landmark: Landmark, collection: LandmarkCollection, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val view = LocalView.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var phase by remember { mutableStateOf(Phase.SEARCHING) }
    var soundOn by remember { mutableStateOf(soundPrefs(context).getBoolean("arSoundOn", true)) }
    var cameraGranted by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
    }
    var arReady by remember { mutableStateOf(false) }
    var arUnavailable by remember { mutableStateOf(!ArTreasureSession.isSupported(context)) }
    var projection by remember { mutableStateOf<ChestProjection?>(null) }
    val tones = remember { runCatching { ToneGenerator(AudioManager.STREAM_MUSIC, 70) }.getOrNull() }

    fun markFound() {
        if (phase != Phase.SEARCHING) return
        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        if (soundOn) tones?.startTone(ToneGenerator.TONE_PROP_BEEP2, 180)
        phase = Phase.FOUND
    }

    fun open() {
        if (phase != Phase.FOUND) return
        view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
        if (soundOn) tones?.startTone(ToneGenerator.TONE_PROP_ACK, 220)
        collection.collect(landmark.id)
        phase = Phase.OPENED
    }

    val session = remember {
        ArTreasureSession(context.applicationContext, "ar_target_${landmark.id}",
            onFound = { markFound() }, onProjection = { projection = it })
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        cameraGranted = granted
        if (!granted) arUnavailable = true
    }
    var installRequested by remember { mutableStateOf(false) }
    fun prepare() {
        if (arUnavailable || arReady || !cameraGranted) return
        val activity = context.findActivity() ?: run { arUnavailable = true; return }
        when (session.create(activity, userRequestedInstall = !installRequested)) {
            ArTreasureSession.Result.READY -> { arReady = true; session.resume() }
            ArTreasureSession.Result.INSTALL_REQUESTED -> installRequested = true
            ArTreasureSession.Result.UNAVAILABLE -> arUnavailable = true
        }
    }

    LaunchedEffect(Unit) {
        // 대상 사진이 아직 없는 보물은 반경 안에 온 것만으로 발견 처리. 사진을 넣으면 자동으로 인식 모드가 된다.
        if (!session.hasTarget) markFound()
        if (!cameraGranted && !arUnavailable) permission.launch(Manifest.permission.CAMERA)
    }
    LaunchedEffect(cameraGranted, arUnavailable) { prepare() }

    val glView = remember {
        GLSurfaceView(context).apply {
            preserveEGLContextOnPause = true
            setEGLContextClientVersion(2)
            setEGLConfigChooser(8, 8, 8, 8, 16, 0)
            setRenderer(session)
            renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
        }
    }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> {
                    if (installRequested && !arReady) prepare() // Play 스토어에서 ARCore 설치 후 돌아온 경우
                    if (arReady) session.resume()
                    glView.onResume()
                }
                Lifecycle.Event.ON_PAUSE -> { glView.onPause(); session.pause() }
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            glView.onPause()
            session.close()
            tones?.release()
        }
    }
    BackHandler(onBack = onDismiss)

    val pulseTransition = rememberInfiniteTransition(label = "pulse")
    val pulse by pulseTransition.animateFloat(0f, 1f, infiniteRepeatable(tween(1400, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "p")
    val density = LocalDensity.current

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        val useAR = arReady && !arUnavailable
        if (useAR) {
            AndroidView(factory = { glView }, modifier = Modifier.fillMaxSize())
            // 월드에 고정된 보물상자(카메라를 움직여도 그 자리에 있다)
            val p = projection
            if (p != null && phase != Phase.OPENED) {
                val widthDp = with(density) { p.width.toDp() }.coerceIn(40.dp, 900.dp)
                Box(Modifier.offset { IntOffset((p.x - p.width / 2).roundToInt(), (p.y - p.width * 0.83f / 2).roundToInt()) }
                    .width(widthDp).height(widthDp * 0.83f).tap(phase == Phase.FOUND) { open() }) {
                    AssetImage("ARChest", Modifier.fillMaxSize(), contentDescription = "보물상자 열기")
                }
            }
        } else {
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(hex(0x9cc78a), hex(0x4f7d4a)))))
            if (phase == Phase.FOUND) {
                Box(Modifier.align(Alignment.Center).width(190.dp).shadow((12 + 14 * pulse).dp, CircleShape, ambientColor = Gold, spotColor = Gold)
                    .tap { open() }) {
                    AssetImage("ARChest", Modifier.fillMaxWidth(), contentDescription = "보물상자 열기")
                }
            }
        }

        if (phase != Phase.OPENED) Reticle(phase == Phase.FOUND, pulse, Modifier.align(Alignment.Center))

        Column(
            Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).padding(horizontal = 20.dp).padding(bottom = 8.dp)
                .alpha(if (phase == Phase.OPENED) 0f else 1f),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.fillMaxWidth()) {
                CircleButton(Icons.AutoMirrored.Filled.ArrowBack, "뒤로", onDismiss)
                Spacer(Modifier.weight(1f))
                CircleButton(if (soundOn) Icons.AutoMirrored.Filled.VolumeUp else Icons.AutoMirrored.Filled.VolumeOff,
                    if (soundOn) "효과음 끄기" else "효과음 켜기") {
                    soundOn = !soundOn
                    soundPrefs(context).edit().putBoolean("arSoundOn", soundOn).apply()
                }
            }
            TitleBadge(phase == Phase.FOUND)
            ClueCapsule(landmark.clue)
            Spacer(Modifier.weight(1f))
            Row(Modifier.fillMaxWidth()) {
                AssetImage("ARFox", Modifier.width(118.dp).rotate(-4f + 7f * pulse))
            }
            OpenButton(phase == Phase.FOUND) { open() }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                SymbolIcon(Icons.Filled.Visibility, Color.White, 18.dp)
                Text(if (phase == Phase.FOUND) "상자를 탭해도 열 수 있어요" else "단서 속 대상을 화면에 비춰보세요",
                    fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.White)
            }
            if (!useAR && !cameraGranted && !arUnavailable) {
                Text("카메라 권한을 허용하면 AR로 보물상자를 볼 수 있어요", fontSize = 12.sp, color = Color.White.copy(alpha = 0.85f))
            }
        }

        AnimatedVisibility(phase == Phase.OPENED, enter = fadeIn(tween(300)), exit = fadeOut()) {
            TreasureReveal(landmark, onDone = onDismiss)
        }
    }
}

@Composable
private fun CircleButton(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(52.dp).shadow(6.dp, CircleShape).background(Cream, CircleShape).tap(onClick = onClick), contentAlignment = Alignment.Center) {
        SymbolIcon(icon, Forest, 24.dp, contentDescription = label)
    }
}

/** 목업에서 떼어낸 배지 그림 위에 제목을 얹는다. */
@Composable
private fun TitleBadge(found: Boolean) {
    val scale by animateFloatAsState(if (found) 1f else 0.97f, spring(dampingRatio = 0.7f), label = "badge")
    Box(Modifier.width(340.dp).scale(scale), contentAlignment = Alignment.Center) {
        AssetImage("ARTitleBadge", Modifier.fillMaxWidth())
        Text(if (found) "보물 발견!" else "보물이 근처에 있어요", fontSize = if (found) 42.sp else 26.sp, fontWeight = FontWeight.Black,
            color = Forest, maxLines = 1, textAlign = TextAlign.Center, modifier = Modifier.width(250.dp).offset(y = 27.dp))
    }
}

@Composable
private fun ClueCapsule(clue: String) {
    val shape = RoundedCornerShape(26.dp)
    Text(
        buildAnnotatedString {
            withStyle(SpanStyle(color = Gold)) { append("단서  ") }
            withStyle(SpanStyle(color = Cream)) { append(clue) }
        },
        fontSize = 16.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, lineHeight = 22.sp,
        modifier = Modifier.widthIn(max = 320.dp).background(Forest, shape).border(2.5.dp, Cream, shape).padding(horizontal = 22.dp, vertical = 10.dp),
    )
}

@Composable
private fun OpenButton(enabled: Boolean, onClick: () -> Unit) {
    val bg = if (enabled) Brush.verticalGradient(listOf(hex(0xf07a62), Coral)) else Brush.verticalGradient(listOf(Color.Gray.copy(alpha = 0.75f), Color.Gray.copy(alpha = 0.75f)))
    Row(
        Modifier.fillMaxWidth().shadow(8.dp, CircleShape).background(bg, CircleShape).border(3.dp, Cream, CircleShape)
            .tap(enabled, onClick).padding(vertical = 20.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        SymbolIcon(if (enabled) Icons.Filled.Inventory2 else Icons.Filled.CenterFocusWeak, Cream, if (enabled) 30.dp else 24.dp)
        Spacer(Modifier.width(10.dp))
        Text(if (enabled) "보물 열기" else "대상을 찾는 중…", fontSize = if (enabled) 28.sp else 22.sp, fontWeight = FontWeight.Black, color = Cream)
    }
}

/** 화면 중앙 조준선: 코너 브래킷 + 바닥 타원. */
@Composable
private fun Reticle(found: Boolean, pulse: Float, modifier: Modifier) {
    val color = if (found) Gold else Cream
    Box(modifier.size(250.dp, 330.dp), contentAlignment = Alignment.TopCenter) {
        Canvas(Modifier.size(250.dp).scale(0.98f + 0.05f * pulse)) {
            val w = size.width; val h = size.height; val len = 34.dp.toPx(); val sw = 5.dp.toPx()
            fun line(a: Offset, b: Offset) = drawLine(color, a, b, sw, StrokeCap.Round)
            line(Offset(0f, len), Offset(0f, 0f)); line(Offset(0f, 0f), Offset(len, 0f))
            line(Offset(w - len, 0f), Offset(w, 0f)); line(Offset(w, 0f), Offset(w, len))
            line(Offset(0f, h - len), Offset(0f, h)); line(Offset(0f, h), Offset(len, h))
            line(Offset(w - len, h), Offset(w, h)); line(Offset(w, h), Offset(w, h - len))
        }
        Canvas(Modifier.offset(y = 125.dp + 78.dp - 23.dp).size(230.dp, 46.dp).alpha(0.55f + 0.45f * pulse)) {
            drawOval(if (found) Gold else Cream.copy(alpha = 0.6f), style = Stroke(3.dp.toPx()))
        }
    }
}

/** 보물 열기 연출: 상자가 흔들리다 빛과 함께 열리고, 보물이 튀어나와 도감 카드가 된다. */
@Composable
private fun TreasureReveal(treasure: Landmark, onDone: () -> Unit) {
    var shake by remember { mutableStateOf(false) }
    var burst by remember { mutableStateOf(false) }
    var showItem by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        shake = true
        delay(750); burst = true
        delay(300); showItem = true
    }
    val shakeAngle by rememberInfiniteTransition(label = "shake").animateFloat(-7f, 7f, infiniteRepeatable(tween(80), RepeatMode.Reverse), label = "s")
    val spin by rememberInfiniteTransition(label = "spin").animateFloat(0f, 360f, infiniteRepeatable(tween(96_000, easing = LinearEasing)), label = "r")
    val burstScale by animateFloatAsState(if (burst) 1f else 0.1f, tween(450), label = "b")
    val itemScale by animateFloatAsState(if (showItem) 1f else 0.2f, spring(dampingRatio = 0.6f), label = "i")
    val gradeColor = treasure.grade.color

    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.72f)), contentAlignment = Alignment.Center) {
        // 뒤에서 도는 빛줄기
        Canvas(Modifier.size(320.dp).scale(burstScale).alpha(if (burst) 1f else 0f)) {
            for (i in 0 until 12) {
                rotate(i * 15f + spin) {
                    drawRoundRect(gradeColor.copy(alpha = 0.35f), topLeft = Offset(center.x - 7.dp.toPx(), center.y - 150.dp.toPx()),
                        size = androidx.compose.ui.geometry.Size(14.dp.toPx(), 300.dp.toPx()),
                        cornerRadius = androidx.compose.ui.geometry.CornerRadius(7.dp.toPx()))
                }
            }
        }
        Box(Modifier.size(320.dp).alpha(if (burst && !showItem) 1f else if (showItem) 0.5f else 0f)
            .background(Brush.radialGradient(listOf(Color.White, gradeColor.copy(alpha = 0f))), CircleShape))
        if (!showItem) {
            AssetImage("ARChest", Modifier.width(200.dp).rotate(if (shake && !burst) shakeAngle else 0f).scale(if (burst) 1.25f else 1f).alpha(if (burst) 0f else 1f))
        }
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).alpha(if (showItem) 1f else 0f),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Spacer(Modifier.weight(1f))
            TreasureIcon(treasure, Modifier.size(220.dp).scale(itemScale).offset(y = if (showItem) 0.dp else 60.dp))
            Text(treasure.grade.title, fontSize = 15.sp, fontWeight = FontWeight.Black, color = Color.White,
                modifier = Modifier.background(gradeColor, CircleShape).padding(horizontal = 14.dp, vertical = 5.dp))
            Text(treasure.name, fontSize = 34.sp, fontWeight = FontWeight.Black, color = Color.White)
            Text(treasure.blurb, fontSize = 15.sp, color = Color.White.copy(alpha = 0.85f), textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 32.dp))
            Spacer(Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                SymbolIcon(Icons.Filled.MenuBook, Gold, 18.dp)
                Text("보물 도감에 등록됐어요", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Gold)
            }
            Box(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 12.dp)
                .background(Brush.verticalGradient(listOf(hex(0xf07a62), Coral)), CircleShape).tap(showItem, onDone).padding(vertical = 16.dp),
                contentAlignment = Alignment.Center) {
                Text("확인", fontSize = 20.sp, fontWeight = FontWeight.Black, color = Cream)
            }
        }
    }
}
