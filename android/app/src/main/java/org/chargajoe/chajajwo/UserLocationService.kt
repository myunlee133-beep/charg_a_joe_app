package org.chargajoe.chajajwo

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import android.os.SystemClock
import android.view.Surface
import android.view.WindowManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import org.chargajoe.chajajwo.data.CampusCoordinate
import kotlin.math.abs

/** 화면에 있을 때만 쓰는 위치 + 나침반. 서버로 보내거나 저장하지 않는다. */
object UserLocationMath {
    fun validCoordinate(latitude: Double, longitude: Double): Boolean =
        latitude.isFinite() && longitude.isFinite() && latitude in -90.0..90.0 && longitude in -180.0..180.0

    fun validFix(ageSeconds: Double, accuracyMeters: Double): Boolean =
        ageSeconds.isFinite() && abs(ageSeconds) <= 30 && accuracyMeters.isFinite() && accuracyMeters >= 0 && accuracyMeters <= 5_000

    fun normalizedHeading(degrees: Double): Double? {
        if (!degrees.isFinite()) return null
        val r = degrees % 360
        return if (r >= 0) r else r + 360
    }

    fun headingRadians(degrees: Double): Double? = normalizedHeading(degrees)?.let { it * Math.PI / 180 }
}

class UserLocationService(private val context: Context) : LocationListener, SensorEventListener {
    enum class Authorization { NOT_DETERMINED, GRANTED, DENIED }

    var coordinate by mutableStateOf<CampusCoordinate?>(null)
        private set
    var headingDegrees by mutableStateOf<Double?>(null)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set
    var approximateLocation by mutableStateOf(false)
        private set
    var authorization by mutableStateOf(Authorization.NOT_DETERMINED)

    /** 권한 요청은 Activity가 한다. 홈 화면이 등록한다. */
    var requestPermission: (() -> Unit)? = null

    private val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var isActive = false
    private var sensorsRunning = false
    private var bestAccuracy = Float.MAX_VALUE
    private var lastFixAt = 0L

    private fun hasFine() = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    private fun hasCoarse() = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    fun refreshAuthorization(deniedAfterRequest: Boolean = false) {
        authorization = when {
            hasFine() || hasCoarse() -> Authorization.GRANTED
            deniedAfterRequest -> Authorization.DENIED
            else -> if (authorization == Authorization.DENIED) Authorization.DENIED else Authorization.NOT_DETERMINED
        }
        approximateLocation = !hasFine() && hasCoarse()
    }

    fun start() {
        if (isActive) return
        isActive = true
        errorMessage = null
        refreshAuthorization()
        val enabled = runCatching { locationManager.isLocationEnabled }.getOrDefault(true)
        if (!enabled) {
            errorMessage = "기기의 위치 서비스가 꺼져 있어요. 설정에서 위치 서비스를 켜주세요."
            isActive = false
            return
        }
        when (authorization) {
            Authorization.NOT_DETERMINED -> requestPermission?.invoke()
            Authorization.GRANTED -> startSensors()
            Authorization.DENIED -> errorMessage = "위치 접근이 허용되지 않았어요. 설정에서 권한을 변경할 수 있어요."
        }
    }

    fun onPermissionResult(granted: Boolean) {
        refreshAuthorization(deniedAfterRequest = !granted)
        if (!isActive) return
        if (granted) {
            errorMessage = null
            startSensors()
        } else {
            coordinate = null; headingDegrees = null
            errorMessage = "위치 접근이 허용되지 않았어요. 설정에서 권한을 변경할 수 있어요."
        }
    }

    fun stop() {
        isActive = false
        if (sensorsRunning) {
            runCatching { locationManager.removeUpdates(this) }
            sensorManager.unregisterListener(this)
            sensorsRunning = false
        }
        coordinate = null
        headingDegrees = null
        bestAccuracy = Float.MAX_VALUE
    }

    @SuppressLint("MissingPermission")
    private fun startSensors() {
        if (!isActive || sensorsRunning) return
        if (!hasFine() && !hasCoarse()) return
        sensorsRunning = true
        val providers = buildList {
            if (hasFine() && locationManager.allProviders.contains(LocationManager.GPS_PROVIDER)) add(LocationManager.GPS_PROVIDER)
            if (locationManager.allProviders.contains(LocationManager.NETWORK_PROVIDER)) add(LocationManager.NETWORK_PROVIDER)
            if (locationManager.allProviders.contains("fused")) add("fused")
        }
        for (provider in providers) {
            runCatching {
                locationManager.requestLocationUpdates(provider, 1000L, 3f, this, Looper.getMainLooper())
                locationManager.getLastKnownLocation(provider)?.let { onLocationChanged(it) }
            }
        }
        val rotation = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (rotation != null) sensorManager.registerListener(this, rotation, SensorManager.SENSOR_DELAY_UI)
        else headingDegrees = null
    }

    override fun onLocationChanged(location: Location) {
        if (!isActive) return
        val age = (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1e9
        val accuracy = if (location.hasAccuracy()) location.accuracy.toDouble() else 5_000.0
        if (!UserLocationMath.validCoordinate(location.latitude, location.longitude) || !UserLocationMath.validFix(age, accuracy)) return
        // 정밀한 GPS가 들어오면 몇 초 동안은 더 부정확한 네트워크 위치로 덮어쓰지 않는다.
        val now = SystemClock.elapsedRealtime()
        if (location.accuracy > bestAccuracy * 2 && now - lastFixAt < 10_000) return
        bestAccuracy = location.accuracy
        lastFixAt = now
        coordinate = CampusCoordinate(location.latitude, location.longitude)
        approximateLocation = !hasFine()
        errorMessage = null
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
    override fun onProviderEnabled(provider: String) {}
    override fun onProviderDisabled(provider: String) {}

    private val rotationMatrix = FloatArray(9)
    private val remapped = FloatArray(9)
    private val orientation = FloatArray(3)
    private var headingAccuracyOK = true

    override fun onSensorChanged(event: SensorEvent) {
        if (!isActive || event.sensor.type != Sensor.TYPE_ROTATION_VECTOR) return
        if (!headingAccuracyOK) { headingDegrees = null; return } // 엉뚱한 방향을 보여주지 않는다
        SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
        // 앱은 세로 고정이므로 기기 위쪽 모서리 방향(이동 방향 아님)을 쓴다.
        @Suppress("DEPRECATION")
        val display = (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay
        val (x, y) = when (display?.rotation) {
            Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
            Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
            Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
            else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
        }
        SensorManager.remapCoordinateSystem(rotationMatrix, x, y, remapped)
        SensorManager.getOrientation(remapped, orientation)
        var degrees = Math.toDegrees(orientation[0].toDouble())
        // 자북 → 진북 보정
        coordinate?.let {
            val field = android.hardware.GeomagneticField(it.latitude.toFloat(), it.longitude.toFloat(), 0f, System.currentTimeMillis())
            degrees += field.declination
        }
        val next = UserLocationMath.normalizedHeading(degrees) ?: return
        val previous = headingDegrees
        if (previous == null || angleDiff(previous, next) >= 3) headingDegrees = next
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
        headingAccuracyOK = accuracy >= SensorManager.SENSOR_STATUS_ACCURACY_LOW
    }

    private fun angleDiff(a: Double, b: Double): Double {
        val d = abs(a - b) % 360
        return if (d > 180) 360 - d else d
    }
}
