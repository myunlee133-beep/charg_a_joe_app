package org.chargajoe.chajajwo

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import org.chargajoe.chajajwo.ui.ContentView
import org.chargajoe.chajajwo.ui.ChajajwoTheme
import org.chargajoe.chajajwo.ui.LocalApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(android.graphics.Color.WHITE, android.graphics.Color.WHITE),
        )
        super.onCreate(savedInstanceState)
        val app = application as ChajajwoApp
        handleVisit(intent)
        // iOS의 -preview-* 실행 인자처럼 CI 스크린샷용 화면을 고를 수 있다.
        intent?.getStringExtra("preview")?.let {
            app.store.previewArgument = it
            if (it == "dining") app.store.tab = Store.Tab.DINING
        }
        setContent {
            CompositionLocalProvider(LocalApp provides app) {
                ChajajwoTheme { ContentView() }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleVisit(intent)
    }

    private fun handleVisit(intent: Intent?) {
        val id = intent?.getStringExtra(VisitReminderReceiver.EXTRA_VISIT_BUILDING) ?: return
        if (!VisitReminderReceiver.isKnownBuilding(id)) return
        val app = application as ChajajwoApp
        app.store.tab = Store.Tab.HOME
        app.store.showDining = false
        app.store.openVisit(id)
    }
}
