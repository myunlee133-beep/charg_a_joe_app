package org.chargajoe.chajajwo.ui

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import org.chargajoe.chajajwo.data.DirectionsURL

/** 버튼이 직접 길찾기 화면을 띄운다. 이미 떠 있는 시트 안에서도 동작한다. */
@Composable
fun DirectionsButton(destination: String?, name: String, modifier: Modifier = Modifier, label: @Composable () -> Unit) {
    var presented by remember { mutableStateOf(false) }
    Box(modifier.alpha(if (destination == null) 0.4f else 1f).tap(destination != null) { presented = true }) { label() }
    if (presented && destination != null) {
        FullScreenDialog(onDismiss = { presented = false }) {
            DirectionsScreen(destination, name, onClose = { presented = false })
        }
    }
}

/** 앱 안의 전체 화면에서 카카오맵 웹 길찾기를 연다. 외부 앱·브라우저·스토어로 나가는 링크는 막는다. */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun DirectionsScreen(destination: String, name: String, onClose: () -> Unit) {
    val context = LocalContext.current
    var isLoading by remember { mutableStateOf(true) }
    var canGoBack by remember { mutableStateOf(false) }
    var isShowingLanding by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var showBlockedLinkNotice by remember { mutableStateOf(false) }

    val webView = remember {
        WebView(context).apply {
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.setSupportMultipleWindows(false)
            settings.javaScriptCanOpenWindowsAutomatically = false
            isLongClickable = false
            setOnLongClickListener { true } // 링크 메뉴로 외부 브라우저·앱을 열지 않는다.
        }
    }
    fun updateNavigation() {
        canGoBack = webView.canGoBack()
        isShowingLanding = android.net.Uri.parse(webView.url ?: "").host?.lowercase() == "applink.map.kakao.com"
    }
    fun load(url: String) {
        DirectionsURL.inAppURL(url)?.let { webView.loadUrl(it) }
    }
    fun reload() {
        errorMessage = null
        showBlockedLinkNotice = false
        // 실패하면 url이 비거나 연결 페이지에 머물 수 있다.
        val current = webView.url
        if (current != null && DirectionsURL.inAppURL(current) != null) webView.reload() else load(destination)
    }

    DisposableEffect(webView) {
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val url = request.url.toString()
                val inApp = DirectionsURL.inAppURL(url)
                if (inApp == null) {
                    // 카카오 모바일 연결 페이지는 앱 스킴을 자동으로 시도한다. 그 페이지의 '설치없이 지도보기'를 그대로 둔다.
                    if (request.hasGesture()) showBlockedLinkNotice = true
                    return true
                }
                if (inApp != url) { view.loadUrl(inApp); return true }
                return false
            }
            override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                isLoading = true; errorMessage = null; showBlockedLinkNotice = false; updateNavigation()
            }
            override fun onPageFinished(view: WebView, url: String?) { isLoading = false; updateNavigation() }
            override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) { updateNavigation() }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (!request.isForMainFrame) return
                isLoading = false
                errorMessage = "인터넷 연결을 확인하고 다시 시도해주세요."
                updateNavigation()
            }
        }
        webView.webChromeClient = WebChromeClient()
        // 다른 길찾기와 쿠키를 섞지 않는다(iOS nonPersistent 저장소 대응).
        CookieManager.getInstance().removeAllCookies(null)
        load(destination)
        onDispose {
            webView.stopLoading()
            webView.destroy()
        }
    }

    BackHandler { if (webView.canGoBack()) webView.goBack() else onClose() }

    Column(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.White)) {
        NavBar(
            title = "길찾기",
            subtitle = name,
            leading = {
                Box(Modifier.size(44.dp).alpha(if (canGoBack) 1f else 0.3f).tap(canGoBack) { errorMessage = null; showBlockedLinkNotice = false; webView.goBack() },
                    contentAlignment = Alignment.Center) { SymbolIcon(Sym.chevronLeft, Cj.tealText, 28.dp, contentDescription = "길찾기 뒤로 가기") }
            },
            actions = {
                Box(Modifier.size(44.dp).tap { reload() }, contentAlignment = Alignment.Center) {
                    SymbolIcon(Sym.refresh, Cj.tealText, 22.dp, contentDescription = "길찾기 새로고침")
                }
                TextButton("닫기", onClick = onClose)
            },
        )
        if (isShowingLanding) {
            Text("‘설치없이 지도보기’를 선택하면 이 화면에서 경로를 확인할 수 있어요.", style = Type.subheadline, color = Cj.tealText,
                modifier = Modifier.fillMaxWidth().background(Cj.successFill).padding(12.dp))
        }
        if (showBlockedLinkNotice) {
            Row(Modifier.fillMaxWidth().background(Cj.inset).padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("외부 앱으로 연결되는 기능이에요. 이 화면에서 길찾기를 계속할 수 있어요.", style = Type.footnote, modifier = Modifier.weight(1f))
                Box(Modifier.size(44.dp).tap { showBlockedLinkNotice = false }, contentAlignment = Alignment.Center) {
                    SymbolIcon(Sym.xmark, Cj.sub, 18.dp, contentDescription = "안내 닫기")
                }
            }
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            AndroidView(factory = { webView }, modifier = Modifier.fillMaxSize().alpha(if (errorMessage == null) 1f else 0f))
            val message = errorMessage
            if (message != null) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    ContentUnavailable("길찾기를 불러오지 못했어요", Sym.wifiOff, message) {
                        Button(onClick = { reload() }, colors = ButtonDefaults.buttonColors(containerColor = Cj.teal)) { Text("다시 시도") }
                    }
                }
            } else if (isLoading) {
                Column(
                    Modifier.align(Alignment.Center).shadow(4.dp, RoundedCornerShape(14.dp)).background(Cj.inset.copy(alpha = 0.95f), RoundedCornerShape(14.dp)).padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    CircularProgressIndicator(Modifier.size(28.dp), color = Cj.sub, strokeWidth = 3.dp)
                    Text("길찾기 불러오는 중", style = Type.subheadline, color = Cj.sub)
                }
            }
        }
    }
}
