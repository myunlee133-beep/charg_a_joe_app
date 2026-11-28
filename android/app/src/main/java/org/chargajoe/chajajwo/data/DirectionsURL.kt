package org.chargajoe.chajajwo.data

import android.net.Uri

data class DirectionsEndpoint(val name: String, val latitude: Double, val longitude: Double) {
    internal val pathComponent: String?
        get() {
            if (name.isBlank() || !latitude.isFinite() || !longitude.isFinite() ||
                latitude !in -90.0..90.0 || longitude !in -180.0..180.0) return null
            // 이름과 좌표는 쉼표로 구분한다. 이름 안의 다른 문장부호는 모두 한 경로 조각에 남긴다.
            val allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
            val encoded = StringBuilder()
            for (b in name.toByteArray(Charsets.UTF_8)) {
                val c = (b.toInt() and 0xff).toChar()
                if (c in allowed && b >= 0) encoded.append(c) else encoded.append("%%%02X".format(b.toInt() and 0xff))
            }
            return "$encoded,${fmt(latitude)},${fmt(longitude)}"
        }

    private fun fmt(value: Double): String {
        // Swift의 Double 문자열화처럼 불필요한 0 없이 쓴다.
        val s = value.toString()
        return if (s.endsWith(".0")) s.dropLast(2) else s
    }
}

enum class DirectionsTransport(val raw: String, val title: String) {
    WALK("walk", "도보"), TRAFFIC("traffic", "대중교통"), CAR("car", "자동차")
}

/** 카카오 공식 웹 길찾기 링크. 모든 길찾기 진입점이 같이 쓴다. */
object DirectionsURL {
    fun destination(name: String, latitude: Double, longitude: Double): String? {
        val path = DirectionsEndpoint(name, latitude, longitude).pathComponent ?: return null
        return "https://map.kakao.com/link/to/$path"
    }

    fun route(start: DirectionsEndpoint, end: DirectionsEndpoint, transport: DirectionsTransport = DirectionsTransport.WALK): String? {
        if (start.latitude == end.latitude && start.longitude == end.longitude) return null
        val startPath = start.pathComponent ?: return null
        val endPath = end.pathComponent ?: return null
        return "https://map.kakao.com/link/by/${transport.raw}/$startPath/$endPath"
    }

    /** 길찾기 화면 안에서는 지도 웹 페이지만 연다. 앱 스킴·스토어 이동은 앱을 떠나지 않게 막는다. */
    fun inAppURL(url: String): String? {
        val uri = try { Uri.parse(url) } catch (e: Exception) { return null }
        val scheme = uri.scheme?.lowercase() ?: return null
        if (scheme != "https" && scheme != "http") return null
        val host = uri.host?.lowercase() ?: return null
        val allowedHost = host == "map.kakao.com" || host.endsWith(".map.kakao.com") ||
            host == "map.daum.net" || host.endsWith(".map.daum.net")
        if (!allowedHost || uri.userInfo != null) return null
        val port = uri.port
        if (!(port == -1 || port == 443 || (scheme == "http" && port == 80))) return null
        return uri.buildUpon().scheme("https").encodedAuthority(host).build().toString()
    }
}
