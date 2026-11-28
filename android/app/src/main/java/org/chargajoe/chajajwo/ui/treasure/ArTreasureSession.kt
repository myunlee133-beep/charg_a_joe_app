package org.chargajoe.chajajwo.ui.treasure

import android.app.Activity
import android.content.Context
import android.graphics.BitmapFactory
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import android.view.WindowManager
import com.google.ar.core.Anchor
import com.google.ar.core.ArCoreApk
import com.google.ar.core.AugmentedImage
import com.google.ar.core.AugmentedImageDatabase
import com.google.ar.core.Config
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Pose
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import org.chargajoe.chajajwo.data.PlaceResources
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.sin

/** 화면 위 보물상자 위치(px)와 크기(px). 카메라 뒤나 화면 밖이면 null. */
data class ChestProjection(val x: Float, val y: Float, val width: Float)

/**
 * iOS ARTreasureView 대응. ARCore로 카메라 화면을 그리고, 보물상자 판(폭 36cm)의 월드 위치를 화면 좌표로 바꿔 알린다.
 * 대상 사진이 있으면 그 사진을 인식한 자리에, 없으면 시작 시 카메라 앞 1m에 상자를 고정한다.
 */
class ArTreasureSession(
    private val context: Context,
    private val targetAsset: String?,
    private val onFound: () -> Unit,
    private val onProjection: (ChestProjection?) -> Unit,
) : GLSurfaceView.Renderer {
    private var session: Session? = null
    private val main = Handler(Looper.getMainLooper())
    private var anchor: Anchor? = null
    private var placed = false
    private var viewportWidth = 1
    private var viewportHeight = 1
    private var startNanos = System.nanoTime()

    // 카메라 배경
    private var cameraTexture = 0
    private var program = 0
    private var positionAttrib = 0
    private var texCoordAttrib = 0
    private val quadCoords: FloatBuffer = floatBuffer(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
    private val quadTexCoords: FloatBuffer = floatBuffer(FloatArray(8))
    private val viewMatrix = FloatArray(16)
    private val projMatrix = FloatArray(16)
    private val viewProj = FloatArray(16)

    companion object {
        private const val TAG = "ArTreasure"
        private const val CHEST_WIDTH_M = 0.36f

        /** ARCore를 쓸 수 있는 기기인지(설치 여부와 별개). */
        fun isSupported(context: Context): Boolean = try {
            val a = ArCoreApk.getInstance().checkAvailability(context)
            a.isSupported || a.isTransient || a == ArCoreApk.Availability.UNKNOWN_CHECKING
        } catch (e: Throwable) { false }

        private fun floatBuffer(values: FloatArray): FloatBuffer =
            ByteBuffer.allocateDirect(values.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(values); position(0) }
    }

    /** ARCore 설치·세션 생성. 실패하면 false(대체 화면 사용). installRequested는 Play 스토어 설치 화면으로 넘어간 경우. */
    fun create(activity: Activity, userRequestedInstall: Boolean): Result {
        if (session != null) return Result.READY
        return try {
            when (ArCoreApk.getInstance().requestInstall(activity, userRequestedInstall)) {
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> return Result.INSTALL_REQUESTED
                ArCoreApk.InstallStatus.INSTALLED -> Unit
                else -> Unit
            }
            val s = Session(context)
            val config = Config(s).apply {
                focusMode = Config.FocusMode.AUTO
                updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                planeFindingMode = Config.PlaneFindingMode.DISABLED
                lightEstimationMode = Config.LightEstimationMode.DISABLED
                targetDatabase(s)?.let { augmentedImageDatabase = it }
            }
            s.configure(config)
            session = s
            Result.READY
        } catch (e: Throwable) {
            Log.w(TAG, "ARCore 세션을 만들 수 없어요: $e")
            Result.UNAVAILABLE
        }
    }

    enum class Result { READY, INSTALL_REQUESTED, UNAVAILABLE }

    /** 대상 사진 drawable(ar_target_<보물 id>)이 있을 때만 이미지 인식 DB를 만든다. */
    private fun targetDatabase(s: Session): AugmentedImageDatabase? {
        val id = PlaceResources.drawableId(targetAsset) ?: return null
        val bitmap = BitmapFactory.decodeResource(context.resources, id) ?: return null
        return try {
            AugmentedImageDatabase(s).apply { addImage(targetAsset, bitmap, 0.3f) }
        } catch (e: Throwable) {
            Log.w(TAG, "대상 사진을 인식용으로 쓸 수 없어요: $e"); null
        }
    }

    val hasTarget: Boolean get() = PlaceResources.drawableId(targetAsset) != null

    fun resume() {
        try { session?.resume() } catch (e: Throwable) { Log.w(TAG, "resume 실패: $e") }
    }

    fun pause() { session?.pause() }

    fun close() {
        anchor?.detach(); anchor = null
        session?.close(); session = null
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        cameraTexture = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTexture)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        program = buildProgram(
            """
            attribute vec4 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() { gl_Position = a_Position; v_TexCoord = a_TexCoord; }
            """.trimIndent(),
            """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_TexCoord;
            uniform samplerExternalOES sTexture;
            void main() { gl_FragColor = texture2D(sTexture, v_TexCoord); }
            """.trimIndent(),
        )
        positionAttrib = GLES20.glGetAttribLocation(program, "a_Position")
        texCoordAttrib = GLES20.glGetAttribLocation(program, "a_TexCoord")
        session?.setCameraTextureName(cameraTexture)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        viewportWidth = width; viewportHeight = height
        GLES20.glViewport(0, 0, width, height)
        @Suppress("DEPRECATION")
        val rotation = (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay?.rotation ?: Surface.ROTATION_0
        session?.setDisplayGeometry(rotation, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val s = session ?: return
        val frame = try {
            s.setCameraTextureName(cameraTexture)
            s.update()
        } catch (e: Throwable) { return }

        if (frame.hasDisplayGeometryChanged()) {
            quadCoords.position(0); quadTexCoords.position(0)
            frame.transformCoordinates2d(Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES, quadCoords, Coordinates2d.TEXTURE_NORMALIZED, quadTexCoords)
        }
        if (frame.timestamp != 0L) drawBackground()

        val camera = frame.camera
        if (camera.trackingState != TrackingState.TRACKING) { post(null); return }

        if (!placed) {
            if (hasTarget) {
                // 대상 사진을 정확히 비추면 그 위에 상자를 둔다.
                for (image in frame.getUpdatedTrackables(AugmentedImage::class.java)) {
                    if (image.trackingState == TrackingState.TRACKING && image.trackingMethod == AugmentedImage.TrackingMethod.FULL_TRACKING) {
                        anchor = image.createAnchor(image.centerPose.compose(Pose.makeTranslation(0f, 0.18f, 0f)))
                        placed = true
                        main.post(onFound)
                        break
                    }
                }
            } else {
                // 대상 사진이 없으면 카메라 앞 1m에 상자를 고정한다(iOS AnchorEntity(world: [0, 0, -1])).
                anchor = s.createAnchor(camera.pose.compose(Pose.makeTranslation(0f, 0f, -1f)))
                placed = true
            }
        }

        val a = anchor
        if (a == null || a.trackingState != TrackingState.TRACKING) { post(null); return }
        camera.getViewMatrix(viewMatrix, 0)
        camera.getProjectionMatrix(projMatrix, 0, 0.05f, 100f)
        Matrix.multiplyMM(viewProj, 0, projMatrix, 0, viewMatrix, 0)
        val t = (System.nanoTime() - startNanos) / 1e9f
        val p = a.pose
        val point = floatArrayOf(p.tx(), p.ty() + sin(t * 2f) * 0.02f, p.tz(), 1f)
        val clip = FloatArray(4)
        Matrix.multiplyMV(clip, 0, viewProj, 0, point, 0)
        if (clip[3] <= 0.01f) { post(null); return }
        val ndcX = clip[0] / clip[3]
        val ndcY = clip[1] / clip[3]
        if (ndcX < -1.5f || ndcX > 1.5f || ndcY < -1.5f || ndcY > 1.5f) { post(null); return }
        val x = (ndcX + 1f) / 2f * viewportWidth
        val y = (1f - ndcY) / 2f * viewportHeight
        val width = CHEST_WIDTH_M * projMatrix[0] / clip[3] * viewportWidth / 2f
        post(ChestProjection(x, y, width))
    }

    private var lastPosted: ChestProjection? = null
    private fun post(value: ChestProjection?) {
        if (value == null && lastPosted == null) return
        lastPosted = value
        main.post { onProjection(value) }
    }

    private fun drawBackground() {
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthMask(false)
        GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTexture)
        quadCoords.position(0); quadTexCoords.position(0)
        GLES20.glVertexAttribPointer(positionAttrib, 2, GLES20.GL_FLOAT, false, 0, quadCoords)
        GLES20.glVertexAttribPointer(texCoordAttrib, 2, GLES20.GL_FLOAT, false, 0, quadTexCoords)
        GLES20.glEnableVertexAttribArray(positionAttrib)
        GLES20.glEnableVertexAttribArray(texCoordAttrib)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(positionAttrib)
        GLES20.glDisableVertexAttribArray(texCoordAttrib)
        GLES20.glDepthMask(true)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
    }

    private fun buildProgram(vertex: String, fragment: String): Int {
        fun shader(type: Int, code: String) = GLES20.glCreateShader(type).also { GLES20.glShaderSource(it, code); GLES20.glCompileShader(it) }
        return GLES20.glCreateProgram().also {
            GLES20.glAttachShader(it, shader(GLES20.GL_VERTEX_SHADER, vertex))
            GLES20.glAttachShader(it, shader(GLES20.GL_FRAGMENT_SHADER, fragment))
            GLES20.glLinkProgram(it)
        }
    }
}
