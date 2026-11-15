package com.badie.app.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import com.badie.app.design.AppTheme
import com.badie.app.design.Appearance
import com.badie.app.design.BadieTheme
import com.badie.app.design.BrutalButton
import com.badie.app.design.ButtonKind
import com.badie.app.design.ButtonSize
import com.badie.app.design.EmptyStateView
import com.badie.app.design.IconButton
import com.badie.app.design.InfoRow
import com.badie.app.design.InsetDivider
import com.badie.app.design.LargeTitleHeader
import com.badie.app.design.MenuRow
import com.badie.app.design.NoticeBanner
import com.badie.app.design.SectionTitle
import com.badie.app.design.StatTile
import com.badie.app.design.Sym
import com.badie.app.design.Toast
import com.badie.app.design.ToastView
import com.badie.app.design.card
import com.badie.app.shell.AppEnvironment
import com.badie.app.shell.CreateMenuSheet
import com.badie.app.shell.LocalEnv
import com.badie.app.shell.MainTabView
import com.badie.app.shell.SplashView
import com.github.takahirom.roborazzi.captureRoboImage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * 把界面渲染成图，放在 app/build/outputs/roborazzi（CI 上作为产物上传），用来和 iPhone 的截图对照。
 * 不比对像素，只出图；页面搬过来一个就在这里加一张。
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w393dp-h852dp-xxhdpi")
class ScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

    private fun shot(name: String, qualifiers: String = "b+zh+Hans", appearance: Appearance = Appearance.Light, content: @Composable () -> Unit) {
        RuntimeEnvironment.setQualifiers("+$qualifiers")
        val environment = AppEnvironment(CoroutineScope(Dispatchers.Unconfined))
        compose.setContent {
            CompositionLocalProvider(LocalEnv provides environment) {
                BadieTheme(appearance) {
                    Box(Modifier.fillMaxSize().background(AppTheme.colors.canvas)) { content() }
                }
            }
        }
        compose.onRoot().captureRoboImage("build/outputs/roborazzi/$name.png")
    }

    @Test
    fun mainTabs() = shot("main-zh") { MainTabView() }

    @Test
    fun mainTabsEnglishDark() = shot("main-en-dark", qualifiers = "en", appearance = Appearance.Dark) { MainTabView() }

    @Test
    fun createMenu() = shot("create-menu-zh") { CreateMenuSheet {} }

    @Test
    fun createMenuJapanese() = shot("create-menu-ja", qualifiers = "ja") { CreateMenuSheet {} }

    @Test
    fun splash() = shot("splash") { SplashView() }

    @Test
    fun components() = shot("components-zh") { Components() }

    @Test
    fun componentsDark() = shot("components-dark", appearance = Appearance.Dark) { Components() }

    /** 设计系统的基础组件摆在一页上 */
    @Composable
    private fun Components() {
        val colors = AppTheme.colors
        Column(Modifier.fillMaxSize().padding(top = 24.dp), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
            LargeTitleHeader("球局", subtitle = "Lv.4+ 中级") {
                IconButton(Sym.plus, "约球", badge = 3) {}
            }
            Column(Modifier.padding(horizontal = AppTheme.Spacing.screen), verticalArrangement = Arrangement.spacedBy(AppTheme.Spacing.md)) {
                ToastView(Toast("资料已保存", Toast.Style.Success))
                BrutalButton("快速匹配", {})
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    BrutalButton("发起球局", {}, Modifier.weight(1f), kind = ButtonKind.Inverse, size = ButtonSize.Medium)
                    BrutalButton("取消", {}, Modifier.weight(1f), kind = ButtonKind.Secondary, size = ButtonSize.Medium)
                    BrutalButton("删除", {}, Modifier.weight(1f), kind = ButtonKind.Destructive, size = ButtonSize.Medium, enabled = false)
                }
                SectionTitle("本周", detail = "3 场", actionTitle = "全部", action = {})
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Spacing.sm)) {
                    StatTile("12", "场次", Modifier.weight(1f))
                    StatTile("58%", "胜率", Modifier.weight(1f), accent = colors.lime)
                    StatTile("4+", "等级", Modifier.weight(1f), accent = colors.lavender)
                }
                Column(Modifier.card()) {
                    InfoRow(Sym.sportscourtFill, "LA Badminton Club", subtitle = "周六 19:00 · 双打")
                    InsetDivider()
                    MenuRow(Sym.person3Fill, "固定局 · 球群", value = "2", badge = 1) {}
                }
                NoticeBanner(Sym.exclamationmarkTriangleFill, "开启定位", actionTitle = "设置", action = {})
                EmptyStateView(Sym.figureBadminton, "附近暂时没有人", tint = colors.sky)
            }
        }
    }
}
