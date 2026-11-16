package com.badie.app

import android.Manifest
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import com.badie.app.design.Appearance
import com.badie.app.design.BadieTheme
import com.badie.app.design.LocalPhotos
import com.badie.app.l10n.L10n
import androidx.lifecycle.lifecycleScope
import com.badie.app.features.onboarding.BrowserAuthSession
import com.badie.app.push.NotificationRouter
import com.badie.app.push.PushRegistry
import com.badie.app.shell.AppLinks
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.RootView

class MainActivity : AppCompatActivity() {
    /** 系统的通知权限框（发出约球请求后问一次，见 PushRegistry.askAfterRequest）。允许了就要推送令牌 */
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) PushRegistry.refresh(this)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        L10n.attach(this)
        val environment = (application as BadieApplication).environment
        PushRegistry.askPermission = { if (Build.VERSION.SDK_INT >= 33) notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS) }
        // 点通知、点链接打开的：转屏重建、从最近任务里打开时不再处理
        if (savedInstanceState == null && intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0) handle(intent)
        setContent {
            val appearance = environment.appState.appearance
            val dark = when (appearance) {
                Appearance.System -> isSystemInDarkTheme()
                Appearance.Light -> false
                Appearance.Dark -> true
            }
            // 内容画到状态栏和导航栏下面；栏上的图标颜色跟着 App 的外观走
            LaunchedEffect(dark) {
                val style = if (dark) SystemBarStyle.dark(Color.TRANSPARENT) else SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
                enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
            }
            CompositionLocalProvider(LocalEnv provides environment, LocalPhotos provides environment.appState.backend.photos) {
                BadieTheme(appearance) { RootView() }
            }
        }
    }

    /** App 开着时点了通知、点了链接，或者 Apple 登录跳回来 */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent) {
        if (NotificationRouter.open(intent)) return
        val link = intent.takeIf { it.action == Intent.ACTION_VIEW }?.dataString ?: return
        if (BrowserAuthSession.receive(link)) return
        AppLinks.open(link, (application as BadieApplication).environment, lifecycleScope)
    }

    override fun onPause() {
        super.onPause()
        BrowserAuthSession.paused()
    }

    override fun onResume() {
        super.onResume()
        // 在浏览器里没走完 Apple 登录就回来了：算取消
        BrowserAuthSession.resumed()
    }

    override fun onStart() {
        super.onStart()
        NotificationRouter.isForeground = true
    }

    override fun onStop() {
        super.onStop()
        NotificationRouter.isForeground = false
    }

    override fun onDestroy() {
        super.onDestroy()
        PushRegistry.askPermission = null
    }
}
