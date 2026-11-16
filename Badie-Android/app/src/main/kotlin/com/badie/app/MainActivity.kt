package com.badie.app

import android.graphics.Color
import android.os.Bundle
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import com.badie.app.design.Appearance
import com.badie.app.design.BadieTheme
import com.badie.app.design.LocalPhotos
import com.badie.app.l10n.L10n
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.RootView

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        L10n.attach(this)
        val environment = (application as BadieApplication).environment
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
}
